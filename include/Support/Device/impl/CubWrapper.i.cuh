/*------------------------------------------------------------------------------
Copyright © 2017 by Nicola Bombieri

CudaStinger is provided under the terms of The MIT License (MIT):

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
the Software, and to permit persons to whom the Software is furnished to do so,
subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
------------------------------------------------------------------------------*/
/**
 * @author Federico Busato
 * Univerity of Verona, Dept. of Computer Science
 * federico.busato@univr.it
 */
#include "Support/Device/SafeCudaAPI.cuh"
#include "Support/Host/Numeric.hpp"
#include <cub.cuh>

namespace xlib {

template<typename T>
CubSortByValue<T>::CubSortByValue(const T* d_in, size_t num_items,
                                  T* d_sorted, T d_in_max) noexcept :
                                        CubWrapper(num_items),
                                        _d_in(d_in), _d_sorted(d_sorted),
                                        _d_in_max(d_in_max) {
    cub::DeviceRadixSort::SortKeys(_d_temp_storage, _temp_storage_bytes,
                                   _d_in, _d_sorted,
                                   _num_items, 0, xlib::ceil_log2(_d_in_max));
    SAFE_CALL( cudaMalloc(&_d_temp_storage, _temp_storage_bytes) )
}

template<typename T>
void CubSortByValue<T>::run() noexcept {
    cub::DeviceRadixSort::SortKeys(_d_temp_storage, _temp_storage_bytes,
                                   _d_in, _d_sorted,
                                   _num_items, 0, xlib::ceil_log2(_d_in_max));
}
//------------------------------------------------------------------------------

template<typename T, typename R>
CubSortByKey<T, R>::CubSortByKey(const T* d_key, const R* d_data_in,
                                     size_t num_items,
                                     T*& d_key_sorted, R*& d_data_out,
                                     T d_key_max) :
                        CubWrapper(num_items),
                        _d_key(d_key), _d_data_in(d_data_in),
                        _d_key_sorted(d_key_sorted),
                        _d_data_out(d_data_out),
                        _d_key_max(d_key_max) {

    cuMalloc(_d_key_sorted, _num_items);
    cuMalloc(_d_data_out, _num_items);
    cub::DeviceRadixSort::SortPairs(_d_temp_storage, _temp_storage_bytes,
                                    _d_key, _d_key_sorted,
                                    _d_data_in, _d_data_out,
                                    _num_items, 0, xlib::ceil_log2(_d_key_max));
    SAFE_CALL( cudaMalloc(&_d_temp_storage, _temp_storage_bytes) )
}

template<typename T, typename R>
CubSortByKey<T, R>::~CubSortByKey() noexcept {
    cuFree(_d_key_sorted, _d_data_out);
}

template<typename T, typename R>
void CubSortByKey<T, R>::run() noexcept {
    cub::DeviceRadixSort::SortPairs(_d_temp_storage, _temp_storage_bytes,
                                    _d_key, _d_key_sorted,
                                    _d_data_in, _d_data_out,
                                    _num_items, 0, xlib::ceil_log2(_d_key_max));
}
//------------------------------------------------------------------------------

template<typename T, typename R>
CubSort2<T, R>::CubSort2(T* d_in1, R* d_in2, size_t num_items,
                        T d_in1_max, R d_in2_max) :
                           CubWrapper(num_items), _d_in1(d_in1), _d_in2(d_in2),
                           _d_in1_tmp(nullptr), _d_in2_tmp(nullptr),
                           _d_in1_max(d_in1_max), _d_in2_max(d_in2_max) {

    cudaMallocX(_d_in1_tmp, _num_items);
    cudaMallocX(_d_in2_tmp, _num_items);
    auto max = std::max(_d_in1_max, d_in2_max);

    cub::DeviceRadixSort::SortPairs(_d_temp_storage, _temp_storage_bytes,
                                    _d_in2, _d_in2_tmp,
                                    _d_in1, _d_in1_tmp,
                                    _num_items, 0, xlib::ceil_log2(max));
    SAFE_CALL( cudaMalloc(&_d_temp_storage, _temp_storage_bytes) )
}

template<typename T, typename R>
CubSort2<T, R>::~CubSort2() noexcept {
    cuFree(_d_in1_tmp, _d_in2_tmp);
}

template<typename T, typename R>
void CubSort2<T, R>::run() noexcept {
    cub::DeviceRadixSort::SortPairs(_d_temp_storage, _temp_storage_bytes,
                                    _d_in2, _d_in2_tmp,
                                    _d_in1, _d_in1_tmp,
                                    _num_items, 0, xlib::ceil_log2(_d_in2_max));

    cub::DeviceRadixSort::SortPairs(_d_temp_storage, _temp_storage_bytes,
                                    _d_in1_tmp, _d_in1,
                                    _d_in2_tmp, _d_in2,
                                    _num_items, 0, xlib::ceil_log2(_d_in1_max));
}
//------------------------------------------------------------------------------
/*
template<typename T>
CubUnique<T>::CubUnique(const T* d_in, size_t num_items, T*& d_unique_batch) :
                           CubWrapper(num_items),
                           _d_in(d_in), _d_unique_batch(d_unique_batch),
                           _d_unique_egdes(nullptr) {

    cuMalloc(_d_unique_egdes);
    cuMalloc(_d_unique_batch, _num_items);

    cub::DeviceSelect::Unique(_d_temp_storage, _temp_storage_bytes,
                              _d_in, _d_unique_batch, _d_unique_egdes,
                              _num_items);
    SAFE_CALL( cudaMalloc(&_d_temp_storage, _temp_storage_bytes) )
}

template<typename T>
CubUnique<T>::~CubUnique() noexcept {
    cuFree(_d_unique_egdes, _d_unique_batch);
}

template<typename T>
int CubUnique<T>::run() noexcept {
    cub::DeviceSelect::Unique(_d_temp_storage, _temp_storage_bytes,
                              _d_in, _d_unique_batch, _d_unique_egdes,
                              _num_items);
    int h_unique_edges;
    cuMemcpyToHost(_d_unique_egdes, h_unique_edges);
    return h_unique_edges;
}
*/
//------------------------------------------------------------------------------

template<typename T, typename R>
CubRunLengthEncode<T, R>::CubRunLengthEncode(const T* d_in, size_t num_items,
                                             T* d_unique_out, R* d_counts_out)
                                             noexcept :
                           CubWrapper(num_items),
                           _d_in(d_in), _d_unique_out(d_unique_out),
                           _d_counts_out(d_counts_out) {

    cuMalloc(_d_num_runs_out, 1);
    cub::DeviceRunLengthEncode::Encode(_d_temp_storage, _temp_storage_bytes,
                                       _d_in, _d_unique_out, _d_counts_out,
                                       _d_num_runs_out, _num_items);
    SAFE_CALL( cudaMalloc(&_d_temp_storage, _temp_storage_bytes) )
}

template<typename T, typename R>
CubRunLengthEncode<T, R>::~CubRunLengthEncode() noexcept {
    cuFree(_d_num_runs_out);
}

template<typename T, typename R>
int CubRunLengthEncode<T, R>::run() noexcept {
    cub::DeviceRunLengthEncode::Encode(_d_temp_storage, _temp_storage_bytes,
                                       _d_in, _d_unique_out, _d_counts_out,
                                       _d_num_runs_out, _num_items);
    int h_num_runs_out;
    cuMemcpyToHost(_d_num_runs_out, h_num_runs_out);
    return h_num_runs_out;
}

//------------------------------------------------------------------------------

template<typename T>
CubExclusiveSum<T>::CubExclusiveSum(const T* d_in, size_t num_items, T* d_out)
                                    noexcept :
                                        CubWrapper(num_items),
                                        _d_in(d_in), _d_out(d_out) {

    cub::DeviceScan::ExclusiveSum(_d_temp_storage, _temp_storage_bytes,
                                  _d_in, _d_out, _num_items);
    SAFE_CALL( cudaMalloc(&_d_temp_storage, _temp_storage_bytes) )
}

template<typename T>
CubExclusiveSum<T>::CubExclusiveSum(T* d_in_out, size_t num_items) noexcept :
                             CubExclusiveSum(d_in_out, num_items, d_in_out) {}

template<typename T>
void CubExclusiveSum<T>::run() noexcept {
    cub::DeviceScan::ExclusiveSum(_d_temp_storage, _temp_storage_bytes,
                                  _d_in, _d_out, _num_items);
}

//------------------------------------------------------------------------------

template<typename T>
CubInclusiveSum<T>::CubInclusiveSum(const T* d_in, size_t num_items, T*& d_out) :
                                   CubWrapper(num_items),
                                   _d_in(d_in), _d_out(d_out) {

    cub::DeviceScan::InclusiveSum(_d_temp_storage, _temp_storage_bytes,
                                  _d_in, _d_out, _num_items);
    SAFE_CALL( cudaMalloc(&_d_temp_storage, _temp_storage_bytes) )
    cuMalloc(d_out, num_items);
}

template<typename T>
CubInclusiveSum<T>::CubInclusiveSum(T* d_in_out, size_t num_items) :
                                    CubWrapper(num_items),
                                    _d_in(nullptr), _d_out(null_ptr_ref),
                                    _d_in_out(d_in_out) {

    cub::DeviceScan::InclusiveSum(_d_temp_storage, _temp_storage_bytes,
                                  d_in_out, d_in_out, num_items);
    SAFE_CALL( cudaMalloc(&_d_temp_storage, _temp_storage_bytes) )
}

template<typename T>
CubInclusiveSum<T>::~CubInclusiveSum() noexcept {
    cuFree(_d_out);
}

template<typename T>
void CubInclusiveSum<T>::run() noexcept {
    if (_d_out != nullptr) {
        cub::DeviceScan::InclusiveSum(_d_temp_storage, _temp_storage_bytes,
                                      _d_in, _d_out, _num_items);
    }
    else {
        cub::DeviceScan::InclusiveSum(_d_temp_storage, _temp_storage_bytes,
                                      _d_in_out, _d_in_out, _num_items);
    }
}

//------------------------------------------------------------------------------
/*
template<typename T>
CubPartitionFlagged<T>::CubPartitionFlagged(const T* d_in, const bool* d_flag,
                                            size_t num_items, T*& d_out) :
                                   CubWrapper(num_items), _d_in(d_in),
                                   _d_out(d_out), _d_flag(d_flag),
                                   _d_num_selected_out(nullptr) {

    cub::DevicePartition::Flagged(_d_temp_storage, _temp_storage_bytes,
                                  d_in, d_flag, d_out, _d_num_selected_out,
                                  num_items);
    SAFE_CALL( cudaMalloc(&_d_temp_storage, _temp_storage_bytes) )
    cuMalloc(d_out, num_items);
    cuMalloc(_d_num_selected_out);
}

template<typename T>
CubPartitionFlagged<T>::~CubPartitionFlagged() noexcept {
    cuFree(_d_out, _d_num_selected_out);
}

template<typename T>
int CubPartitionFlagged<T>::run() noexcept {
    cub::DevicePartition::Flagged(_d_temp_storage, _temp_storage_bytes,
                                  _d_in, _d_flag, _d_out, _d_num_selected_out,
                                  _num_items);
    int h_num_selected;
    cuMemcpyToHost(_d_num_selected_out, h_num_selected);
    return h_num_selected;
}

template<typename T>
void CubPartitionFlagged<T>::run_no_copy() noexcept {
    cub::DevicePartition::Flagged(_d_temp_storage, _temp_storage_bytes,
                                  _d_in, _d_flag, _d_out, _d_num_selected_out,
                                  _num_items);
}
*/
//------------------------------------------------------------------------------

template<typename T>
CubSegmentedReduce<T>::CubSegmentedReduce(int* d_offsets, const T* d_in,
                                          int num_segments, T*& d_out) :
                                   CubWrapper(num_segments), _d_in(d_in),
                                   _d_out(d_out), _d_offsets(d_offsets) {

    cub::DeviceSegmentedReduce::Sum(_d_temp_storage, _temp_storage_bytes,
                                    _d_in, _d_out, num_segments,
                                    _d_offsets, _d_offsets + 1);
    SAFE_CALL( cudaMalloc(&_d_temp_storage, _temp_storage_bytes) )
    cuMalloc(d_out, num_segments);
}

template<typename T>
CubSegmentedReduce<T>::~CubSegmentedReduce() noexcept {
    cuFree(_d_out);
}

template<typename T>
void CubSegmentedReduce<T>::run() noexcept {
    cub::DeviceSegmentedReduce::Sum(_d_temp_storage, _temp_storage_bytes,
                                    _d_in, _d_out, _num_items,
                                    _d_offsets, _d_offsets + 1);
}

//------------------------------------------------------------------------------

template<typename T>
CubSpMV<T>::CubSpMV(T* d_value, int* d_row_offsets, int* d_column_indices,
                    T* d_vector_x, T* d_vector_y,
                    int num_rows, int num_cols, int num_nonzeros) :
                       CubWrapper(0),
                       _d_row_offsets(d_row_offsets),
                       _d_column_indices(d_column_indices),
                       _d_values(d_value),
                       _d_vector_x(d_vector_x), _d_vector_y(d_vector_y),
                       _num_rows(num_rows), _num_cols(num_cols),
                       _num_nonzeros(num_nonzeros) {

    cub::DeviceSpmv::CsrMV(_d_temp_storage, _temp_storage_bytes,
                           _d_values, _d_row_offsets, _d_column_indices,
                           _d_vector_x, _d_vector_y,
                           _num_rows, _num_cols, _num_nonzeros);
    SAFE_CALL( cudaMalloc(&_d_temp_storage, _temp_storage_bytes) )
}
/*
template<typename T>
CubSpMV<T>::~CubSpMV() noexcept {
    cuFree(_d_out);
}*/

template<typename T>
void CubSpMV<T>::run() noexcept {
    cub::DeviceSpmv::CsrMV(_d_temp_storage, _temp_storage_bytes, _d_values,
                           _d_row_offsets, _d_column_indices,
                           _d_vector_x, _d_vector_y,
                           _num_rows, _num_cols, _num_nonzeros);
}


} // namespace xlib
