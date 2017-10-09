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
#include "BatchDeleteKernels.cuh"

namespace hornet {
namespace gpu {

template<typename... VertexTypes, typename... EdgeTypes>
void HORNET::deleteEdgeBatch(BatchUpdate& batch_update) noexcept {
    const unsigned BLOCK_SIZE = 128;
    int num_uniques = batch_preprocessing(batch_update, false);
    //==========================================================================
    size_t  batch_size = batch_update.size();
    vid_t* d_batch_src = batch_update.src_ptr();
    vid_t* d_batch_dst = batch_update.dst_ptr();
    //--------------------------------------------------------------------------
    ///////////////////
    // DELETE KERNEL //
    ///////////////////
    if (_is_sorted) {
        cub_prefixsum.run(_d_counts, num_uniques + 1);

        /*deleteSortedKernel
            <<< xlib::ceil_div<BLOCK_SIZE>(num_uniques), BLOCK_SIZE >>>
            (device_side(), _d_unique, _d_counts, num_uniques, d_batch_dst);
        CHECK_CUDA_ERROR*/
    }
    else {
        vertexDegreeKernel
            <<< xlib::ceil_div<BLOCK_SIZE>(num_uniques), BLOCK_SIZE >>>
            (device_side(), _d_unique, num_uniques, _d_degree_tmp);

        /*deleteUnsortedKernel
            <<< xlib::ceil_div<BLOCK_SIZE>(num_uniques), BLOCK_SIZE >>>
            (device_side(), d_batch_src, d_batch_dst, batch_size,
             _d_degree_tmp);*/
        CHECK_CUDA_ERROR
    }
    //--------------------------------------------------------------------------
                                        //is_insert, get_old_degree
    fixInternalRepresentation(num_uniques, false, false);

    if (_batch_prop == batch_property::CSR)
        build_batch_csr(batch_update, num_uniques, !_is_sorted);
}

} // namespace gpu
} // namespace hornet
