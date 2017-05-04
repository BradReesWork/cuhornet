#include "cuStingerAlg/cuStingerAlg.cuh"    //cuStingerAlg
#include "cuStingerAlg/LoadBalancing/BinarySearch.cuh"
#include "cuStingerAlg/LoadBalancing/VertexBased.cuh"
#include "cuStingerAlg/Operator.cuh"        //Operator
#include "cuStingerAlg/Queue/TwoLevelQueue.cuh"   //Queue

#include <GraphIO/BFS.hpp>              //BFS
#include <GraphIO/GraphStd.hpp>         //GraphStd
#include <Support/Device/Algorithm.cuh> //cu::equal
#include <Support/Host/Timer.hpp>       //Timer

using namespace custinger_alg;
using namespace timer;
using namespace load_balacing;
using namespace custinger;

using dist_t = int;
const dist_t INF = std::numeric_limits<dist_t>::max();

struct BFSData {
    BFSData(size_t allocation) : queue(allocation)  {}

    TwoLevelQueue<vid_t> queue;
    dist_t*              d_distances;
    dist_t               level = 1;
};

__device__ __forceinline__
void VertexInit(vid_t index, void* optional_field) {
    auto bfs_data = *reinterpret_cast<BFSData*>(optional_field);
    bfs_data.d_distances[index] = INF;
}

__device__ __forceinline__
void BFSOperatorAtomic(Vertex src, Edge edge, void* optional_field) {
    auto bfs_data = *reinterpret_cast<BFSData*>(optional_field);
    auto dst = edge.dst();
    auto old = atomicCAS(bfs_data.d_distances + dst, INF, bfs_data.level);
    if (old == INF)
        bfs_data.queue.insert(src.id());     // the vertex dst is active*/
}

__device__ __forceinline__
void BFSOperatorNoAtomic(Vertex src, Edge edge, void* optional_field) {
    auto bfs_data = *reinterpret_cast<BFSData*>(optional_field);
    auto dst = edge.dst();
    if (bfs_data.d_distances[dst] == INF) {
        bfs_data.d_distances[dst] = bfs_data.level;
        bfs_data.queue.insert(src.id());    // the vertex dst is active
    }
}

//==============================================================================

int main(int argc, char* argv[]) {
    using namespace custinger;
    cudaSetDevice(1);
    vid_t bfs_source = 0;
    //--------------------------------------------------------------------------
    //////////////
    // HOST BFS //
    //////////////
    graph::GraphStd<vid_t, eoff_t> graph;
    graph.read(argv[1]);
    graph::BFS<vid_t, eoff_t> bfs(graph);
    bfs.run(bfs_source);

    auto h_distances = bfs.distances();
    //--------------------------------------------------------------------------
    /////////////////
    // DEVICE INIT //
    /////////////////
    cuStingerInit custinger_init(graph.nV(), graph.nE(), graph.out_offsets(),
                                 graph.out_edges());

    cuStinger custiger_graph(custinger_init);

    dist_t* d_distances;
    Allocate alloc(d_distances, graph.nV());
    //--------------------------------------------------------------------------
    //////////////
    // BFS INIT //
    //////////////
    forAllnumV<VertexInit>(custiger_graph, d_distances);
    cuMemcpyToDevice(0, d_distances + bfs_source);
    //TwoLevelQueue<vid_t> queue(graph.nV() * 2);
    //queue.insert(bfs_source);

    load_balacing::BinarySearch lb(graph.out_offsets(), graph.nV());
    //load_balacing::VertexBased lb;

    BFSData bfs_data(graph.nV() * 2);
    bfs_data.queue.insert(bfs_source);

    Timer<DEVICE> TM;
    TM.start();
    //--------------------------------------------------------------------------
    ///////////////////
    // BFS ALGORITHM //
    ///////////////////
    while (bfs_data.queue.size() > 0) {
        lb.traverse_edges<BFSOperatorNoAtomic>((void*) bfs_data);
        bfs_data.queue.swap();
        bfs_data.level++;
    }
    //--------------------------------------------------------------------------
    ////////////////////
    // BFS VALIDATION //
    ////////////////////
    TM.stop();
    TM.print("BFS");

    auto is_correct = cu::equal(h_distances, h_distances + graph.nV(),
                                d_distances);
    std::cout << (is_correct ? "\nCorrect <>\n\n" : "\n! Not Correct\n\n");
}
