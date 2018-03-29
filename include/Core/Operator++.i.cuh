#include <Device/Util/Timer.cuh>

namespace hornets_nest {
namespace detail {

template<typename Operator>
__global__ void forAllKernel(int size, Operator op) {
    int     id = blockIdx.x * blockDim.x + threadIdx.x;
    int stride = blockDim.x * gridDim.x;
    for (auto i = id; i < size; i += stride)
        op(i);
}

template<typename T, typename Operator>
__global__ void forAllKernel(T* __restrict__ array, int size, Operator op) {
    int     id = blockIdx.x * blockDim.x + threadIdx.x;
    int stride = blockDim.x * gridDim.x;
    for (auto i = id; i < size; i += stride) {
        auto value = array[i];
        op(value);
    }
}

template<typename HornetDevice, typename T, typename Operator>
__global__ void forAllVertexPairsKernel(HornetDevice hornet, T* __restrict__ array, int size, Operator op) {
    int     id = blockIdx.x * blockDim.x + threadIdx.x;
    int stride = blockDim.x * gridDim.x;
    for (auto i = id; i < size; i += stride) {
        auto v1_id = array[i].x;
        auto v2_id = array[i].y;
        auto v1 = hornet.vertex(v1_id);
        auto v2 = hornet.vertex(v2_id);
        op(v1, v2);
    }
}

template<typename HornetDevice, typename T, typename Operator>
__global__ void forAllEdgesAdjUnionSequentialKernel(HornetDevice hornet, T* __restrict__ array, unsigned long long size, Operator op, int flag) {
    int     id = blockIdx.x * blockDim.x + threadIdx.x;
    int stride = blockDim.x * gridDim.x;
    for (auto i = id; i < size; i += stride) {
        auto src_vtx = hornet.vertex(array[2*i]);
        auto dst_vtx = hornet.vertex(array[2*i+1]);
        degree_t src_deg = src_vtx.degree();
        degree_t dst_deg = dst_vtx.degree();
        vid_t* src_begin = src_vtx.neighbor_ptr();
        vid_t* dst_begin = dst_vtx.neighbor_ptr();
        vid_t* src_end = src_begin+src_deg-1;
        vid_t* dst_end = dst_begin+dst_deg-1;
        op(src_vtx, dst_vtx, src_begin, src_end, dst_begin, dst_end, flag);
    }
}

namespace adj_union {
    
    __device__ __forceinline__
    void bSearchPath(vid_t* u, vid_t *v, int u_len, int v_len, 
                     vid_t low_vi, vid_t low_ui, 
                     vid_t high_vi, vid_t high_ui, 
                     vid_t* curr_vi, vid_t* curr_ui) {
        vid_t mid_ui, mid_vi;
        int comp1, comp2, comp3;
        while (1) {
            mid_ui = (low_ui+high_ui)/2;
            mid_vi = (low_vi+high_vi+1)/2;

            comp1 = (u[mid_ui] < v[mid_vi]);
            
            if (low_ui == high_ui && low_vi == high_vi) {
                *curr_vi = mid_vi;
                *curr_ui = mid_ui;
                break;
            }
            if (!comp1) {
                low_ui = mid_ui;
                low_vi = mid_vi;
                continue;
            }

            comp2 = (u[mid_ui+1] >= v[mid_vi-1]);
            if (comp1 && !comp2) {
                high_ui = mid_ui+1;
                high_vi = mid_vi-1;
            } else if (comp1 && comp2) {
                comp3 = (u[mid_ui+1] < v[mid_vi]);
                *curr_vi = mid_vi-comp3;
                *curr_ui = mid_ui+comp3;
                break;
            }
       }
    }
}

template<typename HornetDevice, typename T, typename Operator>
__global__ void forAllEdgesAdjUnionBalancedKernel(HornetDevice hornet, T* __restrict__ array, unsigned long long size, unsigned long long threads_per_union, int flag, Operator op) {

    using namespace adj_union;
    int       id = blockIdx.x * blockDim.x + threadIdx.x;
    int queue_id = id / threads_per_union;
    int thread_union_id = threadIdx.x % threads_per_union;
    int block_local_id = threadIdx.x;
    int stride = blockDim.x * gridDim.x;
    int queue_stride = stride / threads_per_union;

    // TODO: dynamic vs. static shared memory allocation?
    __shared__ vid_t pathPoints[256*2]; // i*2+0 = vi, i+2+1 = u_i
    for (auto i = queue_id; i < size; i += queue_stride) {
        auto src_vtx = hornet.vertex(array[2*i]);
        auto dst_vtx = hornet.vertex(array[2*i+1]);
        int srcLen = src_vtx.degree();
        int destLen = dst_vtx.degree();
        int total_work = srcLen + destLen - 1;
        vid_t src = src_vtx.id();
        vid_t dest = dst_vtx.id();

        bool avoidCalc = (src == dest) || (destLen < 2) || (srcLen < 2);
        if (avoidCalc)
            continue;

        // determine u,v where |adj(u)| <= |adj(v)|
        bool sourceSmaller = srcLen < destLen;
        vid_t u = sourceSmaller ? src : dest;
        vid_t v = sourceSmaller ? dest : src;
        auto u_vtx = sourceSmaller ? src_vtx : dst_vtx;
        auto v_vtx = sourceSmaller ? dst_vtx : src_vtx;
        degree_t u_len = sourceSmaller ? srcLen : destLen;
        degree_t v_len = sourceSmaller ? destLen : srcLen;
        vid_t* u_nodes = hornet.vertex(u).neighbor_ptr();
        vid_t* v_nodes = hornet.vertex(v).neighbor_ptr();

        int work_per_thread = total_work/threads_per_union;
        int remainder_work = total_work % threads_per_union;
        int diag_id, next_diag_id;
        diag_id = thread_union_id*work_per_thread + std::min(thread_union_id, remainder_work);
        next_diag_id = (thread_union_id+1)*work_per_thread + std::min(thread_union_id+1, remainder_work);
        //printf("u=%d, v=%d, diag_id=%d, union_id=%d, total_work=%d, work_per_thread=%d, remainder_work=%d\n",
        //        u, v, diag_id, thread_union_id, total_work, work_per_thread, remainder_work);
        vid_t low_ui, low_vi, high_vi, high_ui, ui_curr, vi_curr;
        if (diag_id > 0 && diag_id < total_work) {
            if (diag_id < u_len) {
                low_ui = diag_id-1;
                high_ui = 0;
                low_vi = 0;
                high_vi = diag_id-1;
            } else if (diag_id < v_len) {
                low_ui = u_len-1;
                high_ui = 0;
                low_vi = diag_id-u_len;
                high_vi = diag_id-1;
            } else {
                low_ui = u_len-1;
                high_ui = diag_id - v_len;
                low_vi = diag_id-u_len;
                high_vi = v_len-1;
            }
            bSearchPath(u_nodes, v_nodes, u_len, v_len, low_vi, low_ui, high_vi,
                     high_ui, &vi_curr, &ui_curr);
            pathPoints[block_local_id*2] = vi_curr; 
            pathPoints[block_local_id*2+1] = ui_curr; 
        }

        __syncthreads();

        vid_t vi_begin, ui_begin, vi_end, ui_end;
        vi_begin = ui_begin = vi_end = ui_end = -1;
        int vi_inBounds, ui_inBounds;
        if (diag_id == 0) {
            vi_begin = 0;
            ui_begin = 0;
        } else if (diag_id > 0 && diag_id < total_work) {
            vi_begin = vi_curr;
            ui_begin = ui_curr;
            vi_inBounds = (vi_curr < v_len-1);
            ui_inBounds = (ui_curr < u_len-1);
            if (vi_inBounds && ui_inBounds) {
                int comp = (u_nodes[ui_curr+1] >= v_nodes[vi_curr+1]);
                vi_begin += comp;
                ui_begin += !comp;
            } else {
                vi_begin += vi_inBounds;
                ui_begin += ui_inBounds;
            }
        }
        
        if ((diag_id < total_work) && (next_diag_id >= total_work)) {
            vi_end = v_len - 1;
            ui_end = u_len - 1;
            //printf("u=%d, v=%d intersect, diag_id %d, union_id %d: (%d, %d) -> (%d, %d))\n", 
            //        u, v, diag_id, thread_union_id, vi_begin, ui_begin, vi_end, ui_end); 
        } else if (diag_id < total_work) {
            vi_end = pathPoints[(block_local_id+1)*2];
            ui_end = pathPoints[(block_local_id+1)*2+1];
            //printf("u=%d, v=%d intersect, diag_id %d, union_id %d: (%d, %d) -> (%d, %d))\n", 
            //        u, v, diag_id, thread_union_id, vi_begin, ui_begin, vi_end, ui_end); 
        }
        if (diag_id < total_work) {
            op(u_vtx, v_vtx, u_nodes+ui_begin, u_nodes+ui_end, v_nodes+vi_begin, v_nodes+vi_end, flag);
        }
    }
}

template<typename HornetDevice, typename T, typename Operator>
__global__ void forAllEdgesAdjUnionImbalancedKernel(HornetDevice hornet, T* __restrict__ array, unsigned long long size, unsigned long long threads_per_union, int flag, Operator op) {

    using namespace adj_union;
    auto       id = blockIdx.x * blockDim.x + threadIdx.x;
    auto queue_id = id / threads_per_union;
    auto block_union_offset = blockIdx.x % ((threads_per_union+blockDim.x-1) / blockDim.x); // > 1 if threads_per_union > block size
    auto thread_union_id = ((block_union_offset*blockDim.x)+threadIdx.x) % threads_per_union;
    auto stride = blockDim.x * gridDim.x;
    auto queue_stride = stride / threads_per_union;
    for (auto i = queue_id; i < size; i += queue_stride) {
        auto src_vtx = hornet.vertex(array[2*i]);
        auto dst_vtx = hornet.vertex(array[2*i+1]);
        int srcLen = src_vtx.degree();
        int destLen = dst_vtx.degree();
        vid_t src = src_vtx.id();
        vid_t dest = dst_vtx.id();

        bool avoidCalc = (src == dest) || (destLen < 2) || (srcLen < 2);
        if (avoidCalc)
            continue;

        // determine u,v where |adj(u)| <= |adj(v)|
        bool sourceSmaller = srcLen < destLen;
        vid_t u = sourceSmaller ? src : dest;
        vid_t v = sourceSmaller ? dest : src;
        auto u_vtx = sourceSmaller ? src_vtx : dst_vtx;
        auto v_vtx = sourceSmaller ? dst_vtx : src_vtx;
        degree_t u_len = sourceSmaller ? srcLen : destLen;
        degree_t v_len = sourceSmaller ? destLen : srcLen;
        vid_t* u_nodes = hornet.vertex(u).neighbor_ptr();
        vid_t* v_nodes = hornet.vertex(v).neighbor_ptr();

        int ui_begin, vi_begin, ui_end, vi_end;
        vi_begin = 0;
        vi_end = v_len-1;
        auto work_per_thread = u_len / threads_per_union;
        auto remainder_work = u_len % threads_per_union;
        // divide up work evenly among neighbors of u
        ui_begin = thread_union_id*work_per_thread + std::min(thread_union_id, remainder_work);
        ui_end = (thread_union_id+1)*work_per_thread + std::min(thread_union_id+1, remainder_work) - 1;
        if (ui_end < u_len) {
            op(u_vtx, v_vtx, u_nodes+ui_begin, u_nodes+ui_end, v_nodes+vi_begin, v_nodes+vi_end, flag);
        }
    }
}

template<typename Operator>
__global__ void forAllnumVKernel(vid_t d_nV, Operator op) {
    int     id = blockIdx.x * blockDim.x + threadIdx.x;
    int stride = gridDim.x * blockDim.x;

    for (auto i = id; i < d_nV; i += stride)
        op(i);
}

template<typename Operator>
__global__ void forAllnumEKernel(eoff_t d_nE, Operator op) {
    int      id = blockIdx.x * blockDim.x + threadIdx.x;
    int  stride = gridDim.x * blockDim.x;

    for (eoff_t i = id; i < d_nE; i += stride)
        op(i);
}

template<typename HornetDevice, typename Operator>
__global__ void forAllVerticesKernel(HornetDevice hornet,
                                     Operator     op) {
    int     id = blockIdx.x * blockDim.x + threadIdx.x;
    int stride = gridDim.x * blockDim.x;

    for (vid_t i = id; i < hornet.nV(); i += stride) {
        auto vertex = hornet.vertex(i);
        op(vertex);
    }
}

template<typename HornetDevice, typename Operator>
__global__
void forAllVerticesKernel(HornetDevice              hornet,
                          const vid_t* __restrict__ vertices_array,
                          int                       num_items,
                          Operator                  op) {
    int     id = blockIdx.x * blockDim.x + threadIdx.x;
    int stride = gridDim.x * blockDim.x;

    for (vid_t i = id; i < num_items; i += stride) {
        auto vertex = hornet.vertex(vertices_array[i]);
        op(vertex);
    }
}
/*
template<unsigned BLOCK_SIZE, unsigned ITEMS_PER_BLOCK,
         typename HornetDevice, typename Operator>
__global__
void forAllEdgesKernel(const eoff_t* __restrict__ csr_offsets,
                       HornetDevice               hornet,
                       Operator                   op) {

    __shared__ degree_t smem[ITEMS_PER_BLOCK];
    const auto lambda = [&](int pos, degree_t offset) {
                                auto vertex = hornet.vertex(pos);
                                op(vertex, vertex.edge(offset));
                            };
    xlib::binarySearchLB<BLOCK_SIZE>(csr_offsets, hornet.nV() + 1,
                                     smem, lambda);
}*/

} //namespace detail

//==============================================================================
//==============================================================================
// stub
#define MAX_ADJ_UNIONS_BINS 8
namespace adj_unions {
    struct queue_info {
        unsigned long long queue_sizes[MAX_ADJ_UNIONS_BINS] = {0,};
        vid_t *d_queues[MAX_ADJ_UNIONS_BINS] = {NULL,};
        unsigned long long queue_pos[MAX_ADJ_UNIONS_BINS] = {0,};
        int queue_threads_per[MAX_ADJ_UNIONS_BINS] = {32, 64, 128, 256};
    };

    struct bin_edges {
        HostDeviceVar<queue_info> d_queue_info;
        bool countOnly;
        int total_work, bin_index;

        OPERATOR(Vertex& src, Vertex& dst) {
            // Choose the bin to place this edge into
            if (src.id() >= dst.id()) return; // imposes ordering
            degree_t src_len = src.degree();
            degree_t dst_len = dst.degree();

            degree_t u_len = (src_len <= dst_len) ? src_len : dst_len;
            degree_t v_len = (src_len > dst_len) ? dst_len : src_len;
            unsigned int log_v = 32-__clz(v_len-1);
            int intersect_work = u_len + v_len - 1;
            int binary_work = u_len * log_v;
            int METHOD = (5*intersect_work >= binary_work);
            total_work = METHOD ? u_len : u_len+v_len-1;
            int cutoff = METHOD ? 3 : 31;
            int i = MAX_ADJ_UNIONS_BINS/2;
            
            int W;
            while (i > 0) {
                W = d_queue_info.ptr()->queue_threads_per[i];
                if ((total_work+W-1)/W >= cutoff)
                    break;
                i-=1;
            }
            bin_index = METHOD*(MAX_ADJ_UNIONS_BINS/2)+i;
            // Either count or add the item to the appropriate queue
            if (countOnly)
                atomicAdd(&(d_queue_info.ptr()->queue_sizes[bin_index]), 1ULL);
            else {
                // How do I get the value returned by atomicAdd?
                int id = atomicAdd(&(d_queue_info.ptr()->queue_pos[bin_index]), 1ULL);
                d_queue_info.ptr()->d_queues[bin_index][id*2] = src.id();
                d_queue_info.ptr()->d_queues[bin_index][id*2+1] = dst.id();
            }
        }
    };
}


template<typename HornetClass, typename Operator>
void forAllAdjUnions(HornetClass&         hornet,
                     const Operator&      op)
{
    forAllAdjUnions(hornet, TwoLevelQueue<vid2_t>(hornet, 0), op); // TODO: why can't just pass in 0?
}

template<typename HornetClass, typename Operator>
void forAllAdjUnions(HornetClass&          hornet,
                     TwoLevelQueue<vid2_t> vertex_pairs,
                     const Operator&       op)
{
    using namespace adj_unions;
    HostDeviceVar<queue_info> hd_queue_info;

    load_balancing::VertexBased1 load_balancing ( hornet );

    timer::Timer<timer::DEVICE> TM(5);
    TM.start();
    //TM.start();
    if (vertex_pairs.size())
        forAllVertexPairs(hornet, vertex_pairs, bin_edges {hd_queue_info, true});
    else
        forAllEdgeVertexPairs(hornet, bin_edges {hd_queue_info, true}, load_balancing);

    //TM.stop();
    //TM.print("counting queues:");
    //TM.reset();
    hd_queue_info.sync();

    for (auto i = 0; i < MAX_ADJ_UNIONS_BINS; i++)
        printf("queue=%d number of edges: %llu\n", i, hd_queue_info().queue_sizes[i]);
    // Next, add each edge into the correct corresponding queue
    //TM.start();
    for (auto i = 0; i < MAX_ADJ_UNIONS_BINS; i++)
        cudaMalloc(&(hd_queue_info().d_queues[i]), 2*hd_queue_info().queue_sizes[i]*sizeof(vid_t));
    //TM.stop();
    //TM.print("queue allocation:");
    //TM.start();
    //TM.reset();

    if (vertex_pairs.size())
        forAllVertexPairs(hornet, vertex_pairs, bin_edges {hd_queue_info, false});
    else
        forAllEdgeVertexPairs(hornet, bin_edges {hd_queue_info, false}, load_balancing);

    //TM.stop();
    //TM.print("adding to queues:");
    //TM.reset();
    TM.stop();
    TM.print("queueing and binning:");
    TM.reset();

    hd_queue_info.sync();

    // Phase 2: run the operator on each queued edge as appropriate
    for (auto bin = 0; bin < MAX_ADJ_UNIONS_BINS; bin++) {
        if (hd_queue_info().queue_sizes[bin] == 0) continue;
        int threads_per = hd_queue_info().queue_threads_per[bin % (MAX_ADJ_UNIONS_BINS/2)]; 
        TM.start();
        if (bin < MAX_ADJ_UNIONS_BINS/2) { 
            forAllEdgesAdjUnionBalanced(hornet, hd_queue_info().d_queues[bin], hd_queue_info().queue_pos[bin], op, threads_per, 0);
        } else if (bin >= MAX_ADJ_UNIONS_BINS/2) {
            forAllEdgesAdjUnionImbalanced(hornet, hd_queue_info().d_queues[bin], hd_queue_info().queue_pos[bin], op, threads_per, 1);
        }
        
        TM.stop();
        TM.print("queue processing:");
        TM.reset();
    }
}


template<typename HornetClass, typename Operator>
void forAllEdgesAdjUnionSequential(HornetClass &hornet, vid_t* queue, const unsigned long long size, const Operator &op, int flag) {
    if (size == 0)
        return;
    detail::forAllEdgesAdjUnionSequentialKernel
        <<< xlib::ceil_div<BLOCK_SIZE_OP2>(size), BLOCK_SIZE_OP2 >>>
        (hornet.device_side(), queue, size, op, flag);
    CHECK_CUDA_ERROR
}

template<typename HornetClass, typename Operator>
void forAllEdgesAdjUnionBalanced(HornetClass &hornet, vid_t* queue, const unsigned long long size, const Operator &op, unsigned long long threads_per_union, int flag) {
    //printf("queue size: %llu\n", size);
    auto grid_size = size*threads_per_union;
    auto _size = size;
    while (grid_size > (1ULL<<31)) {
        // FIXME get 1<<31 from Hornet
        _size >>= 1;
        grid_size = _size*threads_per_union;
    }
    if (size == 0)
        return;
    detail::forAllEdgesAdjUnionBalancedKernel
        <<< xlib::ceil_div<BLOCK_SIZE_OP2>(grid_size), BLOCK_SIZE_OP2 >>>
        (hornet.device_side(), queue, size, threads_per_union, flag, op);
    CHECK_CUDA_ERROR
}

template<typename HornetClass, typename Operator>
void forAllEdgesAdjUnionImbalanced(HornetClass &hornet, vid_t* queue, const unsigned long long size, const Operator &op, unsigned long long threads_per_union, int flag) {
    //printf("queue size: %llu\n", size);
    auto grid_size = size*threads_per_union;
    auto _size = size;
    while (grid_size > (1ULL<<31)) {
        // FIXME get 1<<31 from Hornet
        _size >>= 1;
        grid_size = _size*threads_per_union;
    }
    if (size == 0)
        return;
    detail::forAllEdgesAdjUnionImbalancedKernel
        <<< xlib::ceil_div<BLOCK_SIZE_OP2>(grid_size), BLOCK_SIZE_OP2 >>>
        (hornet.device_side(), queue, size, threads_per_union, flag, op);
    CHECK_CUDA_ERROR
}

template<typename Operator>
void forAll(size_t size, const Operator& op) {
    if (size == 0)
        return;
    detail::forAllKernel
        <<< xlib::ceil_div<BLOCK_SIZE_OP2>(size), BLOCK_SIZE_OP2 >>>
        (size, op);
    CHECK_CUDA_ERROR
}

template<typename T, typename Operator>
void forAll(const TwoLevelQueue<T>& queue, const Operator& op) {
    auto size = queue.size();
    if (size == 0)
        return;
    detail::forAllKernel
        <<< xlib::ceil_div<BLOCK_SIZE_OP2>(size), BLOCK_SIZE_OP2 >>>
        (queue.device_input_ptr(), size, op);
    CHECK_CUDA_ERROR
}

template<typename HornetClass, typename T, typename Operator>
void forAllVertexPairs(HornetClass&            hornet,
                       const TwoLevelQueue<T>& queue,
                       const Operator&         op) {
    auto size = queue.size();
    if (size == 0)
        return;
    detail::forAllVertexPairsKernel
        <<< xlib::ceil_div<BLOCK_SIZE_OP2>(size), BLOCK_SIZE_OP2 >>>
        (hornet.device_side(), queue.device_input_ptr(), size, op);
    CHECK_CUDA_ERROR
}

//------------------------------------------------------------------------------

template<typename HornetClass, typename Operator>
void forAllnumV(HornetClass& hornet, const Operator& op) {
    detail::forAllnumVKernel
        <<< xlib::ceil_div<BLOCK_SIZE_OP2>(hornet.nV()), BLOCK_SIZE_OP2 >>>
        (hornet.nV(), op);
    CHECK_CUDA_ERROR
}

//------------------------------------------------------------------------------

template<typename HornetClass, typename Operator>
void forAllnumE(HornetClass& hornet, const Operator& op) {
    detail::forAllnumEKernel
        <<< xlib::ceil_div<BLOCK_SIZE_OP2>(hornet.nE()), BLOCK_SIZE_OP2 >>>
        (hornet.nE(), op);
    CHECK_CUDA_ERROR
}

//==============================================================================

template<typename HornetClass, typename Operator>
void forAllVertices(HornetClass& hornet, const Operator& op) {
    detail::forAllVerticesKernel
        <<< xlib::ceil_div<BLOCK_SIZE_OP2>(hornet.nV()), BLOCK_SIZE_OP2 >>>
        (hornet.device_side(), op);
    CHECK_CUDA_ERROR
}

//------------------------------------------------------------------------------

template<typename HornetClass, typename Operator, typename LoadBalancing>
void forAllEdges(HornetClass&         hornet,
                 const Operator&      op,
                 const LoadBalancing& load_balancing) {

    load_balancing.apply(hornet, op);
}

template<typename HornetClass, typename Operator, typename LoadBalancing>
void forAllEdgeVertexPairs(HornetClass&         hornet,
                           const Operator&      op,
                           const LoadBalancing& load_balancing) {
    load_balancing.applyVertexPairs(hornet, op);
}

//==============================================================================

template<typename HornetClass, typename Operator, typename T>
void forAllVertices(HornetClass&    hornet,
                    const vid_t*    vertex_array,
                    int             size,
                    const Operator& op) {
    detail::forAllVerticesKernel
        <<< xlib::ceil_div<BLOCK_SIZE_OP2>(size), BLOCK_SIZE_OP2 >>>
        (hornet.device_side(), vertex_array, size, op);
    CHECK_CUDA_ERROR
}

template<typename HornetClass, typename Operator>
void forAllVertices(HornetClass&                hornet,
                    const TwoLevelQueue<vid_t>& queue,
                    const Operator&             op) {
    auto size = queue.size();
    detail::forAllVerticesKernel
        <<< xlib::ceil_div<BLOCK_SIZE_OP2>(size), BLOCK_SIZE_OP2 >>>
        (hornet.device_side(), queue.device_input_ptr(), size, op);
    CHECK_CUDA_ERROR
}

template<typename HornetClass, typename Operator, typename LoadBalancing>
void forAllEdges(HornetClass&    hornet,
                 const vid_t*    vertex_array,
                 int             size,
                 const Operator& op,
                 const LoadBalancing& load_balancing) {
    load_balancing.apply(hornet, vertex_array, size, op);
}
/*
template<typename HornetClass, typename Operator, typename LoadBalancing>
void forAllEdges(HornetClass& hornet,
                 const TwoLevelQueue<vid_t>& queue,
                 const Operator& op, const LoadBalancing& load_balancing) {
    load_balancing.apply(hornet, queue.device_input_ptr(),
                        queue.size(), op);
    //queue.kernel_after();
}*/

template<typename HornetClass, typename Operator, typename LoadBalancing>
void forAllEdges(HornetClass&                hornet,
                 const TwoLevelQueue<vid_t>& queue,
                 const Operator&             op,
                 const LoadBalancing&        load_balancing) {
    load_balancing.apply(hornet, queue.device_input_ptr(), queue.size(), op);
}

} // namespace hornets_nest
