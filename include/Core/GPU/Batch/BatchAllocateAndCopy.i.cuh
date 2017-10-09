
/**
 * @author Federico Busato                                                  <br>
 *         Univerity of Verona, Dept. of Computer Science                   <br>
 *         federico.busato@univr.it
 * @date September, 2017
 * @version v2
 *
 * @copyright Copyright © 2017 Hornet. All rights reserved.
 *
 * @license{<blockquote>
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *
 * * Redistributions of source code must retain the above copyright notice, this
 *   list of conditions and the following disclaimer.
 * * Redistributions in binary form must reproduce the above copyright notice,
 *   this list of conditions and the following disclaimer in the documentation
 *   and/or other materials provided with the distribution.
 * * Neither the name of the copyright holder nor the names of its
 *   contributors may be used to endorse or promote products derived from
 *   this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
 * AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
 * LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
 * CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 * SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 * INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
 * CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 * ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
 * POSSIBILITY OF SUCH DAMAGE.
 * </blockquote>}
 */
#include "BatchCopyKernels.cuh"

//#define DEBUG_FIXINTERNAL

namespace hornet {
namespace gpu {


template<typename... VertexTypes, typename... EdgeTypes>
void HORNET::allocateEdgeDeletion(size_t max_batch_size,
                                  BatchProperty batch_prop) noexcept {
    _batch_prop = batch_prop;
    if (_batch_prop == batch_property::GEN_INVERSE)
        max_batch_size *= 2u;
    auto csr_size = std::min(max_batch_size, static_cast<size_t>(_nV));

    allocatePrepocessing(max_batch_size, csr_size);

    if (_batch_prop != batch_property::IN_PLACE)
        allocateOOPEdgeDeletion(csr_size);
    else {
        allocateInPlaceUpdate(csr_size);
        ERROR("Edge Batch deletion IN-PLACE not implemented")
    }
}

template<typename... VertexTypes, typename... EdgeTypes>
void HORNET::allocateEdgeInsertion(size_t max_batch_size,
                                   BatchProperty batch_prop) noexcept {
    _batch_prop = batch_prop;
    if (_batch_prop == batch_property::GEN_INVERSE)
        max_batch_size *= 2u;
    auto csr_size = std::min(max_batch_size, static_cast<size_t>(_nV));

    allocatePrepocessing(max_batch_size, csr_size);

    if (_batch_prop == batch_property::IN_PLACE)
        allocateInPlaceUpdate(csr_size);
    else
        ERROR("Edge Batch deletion OUT-OF-PLACE not implemented")

    if (_batch_prop == batch_property::REMOVE_BATCH_DUPLICATE || _is_sorted)
        cub_sort_pair.initialize(max_batch_size, false);
}

//==============================================================================

template<typename... VertexTypes, typename... EdgeTypes>
void HORNET::allocatePrepocessing(size_t max_batch_size, size_t csr_size)
                                  noexcept {
    cub_prefixsum.initialize(max_batch_size);
    cub_runlength.initialize(max_batch_size);
    cub_select_flag.initialize(max_batch_size);
    cub_sort.initialize(max_batch_size);

    cuMalloc(_d_batch_src,    max_batch_size);
    cuMalloc(_d_batch_dst,    max_batch_size);
    cuMalloc(_d_tmp_sort_src, max_batch_size);
    cuMalloc(_d_tmp_sort_dst, max_batch_size);
    cuMalloc(_d_counts,       csr_size + 1);
    cuMalloc(_d_unique,       csr_size);

    if (_batch_prop == batch_property::REMOVE_CROSS_DUPLICATE) {
        auto used_size = _batch_prop == batch_property::REMOVE_BATCH_DUPLICATE ?
                            csr_size : max_batch_size;
        cuMalloc(_d_degree_tmp, used_size + 1);
        cuMalloc(_d_flags,      used_size);
        cuMemset(_d_flags,      used_size, 0x01);    //all true
    }
}

template<typename... VertexTypes, typename... EdgeTypes>
void HORNET::allocateOOPEdgeDeletion(size_t csr_size) noexcept {
    cuMalloc(_d_degree_tmp,  csr_size + 1,
             _d_degree_new,  csr_size + 1,
             _d_tmp,         _nE,
             _d_ptrs_array,  csr_size,
             _d_inverse_pos, _nV);
}

template<typename... VertexTypes, typename... EdgeTypes>
void HORNET::allocateInPlaceUpdate(size_t csr_size) noexcept {
    cuMalloc(_d_queue_new_degree, csr_size);
    cuMalloc(_d_queue_new_ptr,    csr_size);
    cuMalloc(_d_queue_old_ptr,    csr_size);
    cuMalloc(_d_queue_old_degree, csr_size + 1);
    cuMalloc(_d_queue_id,         csr_size);
    cuMalloc(_d_queue_size, 1);

    _h_queue_id = new int[csr_size];
    cuMallocHost(_h_queue_new_ptr,    csr_size);
    cuMallocHost(_h_queue_new_degree, csr_size);
    cuMallocHost(_h_queue_old_ptr,    csr_size);
    cuMallocHost(_h_queue_old_degree, csr_size + 1);
}

//==============================================================================
//==============================================================================

template<typename... VertexTypes, typename... EdgeTypes>
void HORNET::copySparseToContinuos(const degree_t* prefixsum,
                                   int             prefixsum_size,
                                   int             total_sum,
                                   void**          sparse_ptrs,
                                   void*           continuous_array) noexcept {
    const unsigned BLOCK_SIZE = 256;
    const int SMEM = xlib::SMemPerBlock<BLOCK_SIZE, int>::value;
    int num_blocks = xlib::ceil_div<SMEM>(total_sum);

    copySparseToContinuosKernel<BLOCK_SIZE, SMEM, NUM_ETYPES, EdgeTypes...>
        <<< num_blocks, BLOCK_SIZE >>>
        (prefixsum, prefixsum_size, sparse_ptrs, continuous_array);
    CHECK_CUDA_ERROR
}

template<typename... VertexTypes, typename... EdgeTypes>
void HORNET::copySparseToContinuos(const degree_t* prefixsum,
                                   int             prefixsum_size,
                                   int             total_sum,
                                   void**          sparse_ptrs,
                                   const int*      continuos_offsets,
                                   void*           continuous_array) noexcept {
    const unsigned BLOCK_SIZE = 256;
    const int SMEM = xlib::SMemPerBlock<BLOCK_SIZE, int>::value;
    int num_blocks = xlib::ceil_div<SMEM>(total_sum);

    copySparseToContinuosKernel<BLOCK_SIZE, SMEM, EdgeTypes...>
        <<< num_blocks, BLOCK_SIZE >>>
        (prefixsum, prefixsum_size, sparse_ptrs,
         continuos_offsets, continuous_array);
    CHECK_CUDA_ERROR
}

template<typename... VertexTypes, typename... EdgeTypes>
void HORNET::copyContinuosToSparse(const degree_t* prefixsum,
                                   int             prefixsum_size,
                                   int             total_sum,
                                   void*           continuous_array,
                                   void**          sparse_ptrs) noexcept {
    const unsigned BLOCK_SIZE = 256;
    const int SMEM = xlib::SMemPerBlock<BLOCK_SIZE, degree_t>::value;
    int num_blocks = xlib::ceil_div<SMEM>(total_sum);

    copyContinuosToSparseKernel<BLOCK_SIZE, SMEM, EdgeTypes...>
        <<< num_blocks, BLOCK_SIZE >>>
        (prefixsum, prefixsum_size, continuous_array, sparse_ptrs);
    CHECK_CUDA_ERROR
}

template<typename... VertexTypes, typename... EdgeTypes>
void HORNET::copySparseToSparse(const degree_t* d_prefixsum,
                                int             prefixsum_size,
                                int             prefixsum_total,
                                void**          d_old_ptrs,
                                void**          d_new_ptrs)
                                noexcept {
    const unsigned BLOCK_SIZE = 256;
    const int SMEM = xlib::SMemPerBlock<BLOCK_SIZE, degree_t>::value;
    int num_blocks = xlib::ceil_div<SMEM>(prefixsum_total);

    copySparseToSparseKernel<BLOCK_SIZE, SMEM, EdgeTypes...>
        <<< num_blocks, BLOCK_SIZE >>>
        (d_prefixsum, prefixsum_size, d_old_ptrs, d_new_ptrs);
    CHECK_CUDA_ERROR
}

#undef DEBUG_FIXINTERNAL

} // namespace gpu
} // namespace hornet
