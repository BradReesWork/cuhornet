/**
 * @author Federico Busato                                                  <br>
 *         Univerity of Verona, Dept. of Computer Science                   <br>
 *         federico.busato@univr.it
 * @date April, 2017
 * @version v2
 *
 * @copyright Copyright © 2017 cuStinger. All rights reserved.
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
#include "Csr/Csr.hpp"
#include "GlobalSpace.cuh"          //d_nV
#include "Csr/CsrTypes.cuh"

namespace csr {

void Csr::initializeGlobal(byte_t* (&vertex_data_ptrs)[NUM_VTYPES],
                           byte_t* (&edge_data_ptrs)[NUM_ETYPES]) noexcept {
    cuMemcpyToSymbol(_nV, d_nV);
    cuMemcpyToSymbol(vertex_data_ptrs, NUM_VTYPES, d_vertex_data_ptrs);
    cuMemcpyToSymbol(edge_data_ptrs, NUM_VTYPES, d_edge_data_ptrs);
}

//==============================================================================

__global__ void printKernel() {
    for (vid_t i = 0; i < d_nV; i++) {
        auto vertex = Vertex(i);
        auto degree = vertex.degree();
        //auto field0 = vertex.field<0>();
        printf("%d [%d]:    ", i, vertex.degree());

        for (degree_t j = 0; j < vertex.degree(); j++) {
            auto   edge = vertex.edge(j);
            /*auto weight = edge.weight();
            auto  time1 = edge.time_stamp1();
            auto field0 = edge.field<0>();
            auto field1 = edge.field<1>();*/

            printf("%d    ", edge.dst());
        //    d_array[j] = edge.dst();
        }
        printf("\n");
    }
}

void Csr::print() noexcept {
    if (sizeof(degree_t) == 4 && sizeof(vid_t) == 4) {
        printKernel<<<1, 1>>>();
        CHECK_CUDA_ERROR
    }
    else
        WARNING("Graph print is enable only with degree_t/vid_t of size 4 bytes")
}

} // namespace csr
