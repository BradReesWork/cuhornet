/**
 * @author Federico Busato                                                  <br>
 *         Univerity of Verona, Dept. of Computer Science                   <br>
 *         federico.busato@univr.it
 * @date August, 2017
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
#include "Device/SafeCudaAPI.cuh"
#include "Device/PrintExt.cuh"

namespace hornet {
namespace gpu {

inline BatchProperty::BatchProperty(const detail::BatchPropEnum& obj) noexcept :
    xlib::PropertyClass<detail::BatchPropEnum, BatchProperty>(obj) {}

//==============================================================================

inline BatchUpdate::BatchUpdate(vid_t* src_array, vid_t* dst_array,
                                int batch_size, BatchType batch_type)
                                    noexcept : _src_array(src_array),
                                               _dst_array(dst_array),
                                               _original_size(batch_size),
                                               _batch_type(batch_type) {}

inline vid_t* BatchUpdate::original_src_ptr() const noexcept {
    return _src_array;
}

inline vid_t* BatchUpdate::original_dst_ptr() const noexcept {
    return _dst_array;
}

inline int BatchUpdate::original_size() const noexcept {
    return _original_size;
}

inline BatchType BatchUpdate::type() const noexcept {
    return _batch_type;
}

inline void BatchUpdate::print() const noexcept {
    if (_batch_type == BatchType::HOST) {
        xlib::printArray(_src_array, _original_size,
                         "Source/Destination Arrays:\n");
        xlib::printArray(_dst_array, _original_size);
    }
    else {
        cu::printArray(_src_array, _original_size,
                       "Source/Destination Arrays:\n");
        cu::printArray(_dst_array, _original_size);
    }
}

//------------------------------------------------------------------------------

HOST_DEVICE int BatchUpdate::size() const noexcept {
    return _batch_size;
}

HOST_DEVICE vid_t* BatchUpdate::src_ptr() const noexcept {
    return _d_src_array;
}

HOST_DEVICE vid_t* BatchUpdate::dst_ptr() const noexcept {
    return _d_dst_array;
}

HOST_DEVICE const eoff_t* BatchUpdate::csr_offsets_ptr() const noexcept {
    assert(_d_offsets != nullptr);
    return _d_offsets;
}

HOST_DEVICE int BatchUpdate::csr_offsets_size() const noexcept {
    assert(_offsets_size != 0);
    return _offsets_size;
}

__device__ __forceinline__
vid_t BatchUpdate::src(int index) const {
    assert(index < _batch_size);
    return _d_src_array[index];
}

__device__ __forceinline__
vid_t BatchUpdate::dst(int index) const {
    assert(index < _batch_size);
    return _d_dst_array[index];
}

__device__ __forceinline__
vid_t BatchUpdate::csr_id(int index) const {
    assert(_d_ids != nullptr);
    assert(index < _offsets_size);
    return _d_ids[index];
}

__device__ __forceinline__
int BatchUpdate::csr_offsets(int index) const {
    assert(_d_offsets != nullptr);
    assert(index < _offsets_size);
    return _d_offsets[index];
}

__device__ __forceinline__
int BatchUpdate::csr_src_pos(vid_t vertex_id) const {
    assert(_d_inverse_pos != nullptr);
    assert(vertex_id < _nV);
    return _d_inverse_pos[vertex_id];
}

__device__ __forceinline__
int BatchUpdate::csr_wide_offsets(vid_t vertex_id) const {
    assert(_d_inverse_pos != nullptr);
    assert(vertex_id < _nV);
    //return _d_offsets[_d_inverse_pos[vertex_id]];
    return _d_wide_offsets[vertex_id];
}

inline void BatchUpdate::change_size(int d_batch_size) noexcept {
    _batch_size  = d_batch_size;
}

inline void BatchUpdate::set_device_ptrs(vid_t* d_src_array, vid_t* d_dst_array,
                                         int d_batch_size) noexcept {
    _d_src_array = d_src_array;
    _d_dst_array = d_dst_array;
    _batch_size  = d_batch_size;
}

inline void BatchUpdate::set_csr(const vid_t*  d_ids,
                                 const eoff_t* d_offsets, int offsets_size,
                                 const eoff_t* d_inverse_pos) noexcept {
    _d_offsets     = d_offsets;
    _offsets_size  = offsets_size;
    _d_inverse_pos = d_inverse_pos;
}

inline void BatchUpdate::set_wide_csr(const eoff_t* d_wide_offsets) noexcept {
    _d_wide_offsets = d_wide_offsets;
}

} // namespace gpu
} // namespace hornet
