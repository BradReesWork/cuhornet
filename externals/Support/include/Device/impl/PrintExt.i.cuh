/**
 * @author Federico Busato                                                  <br>
 *         Univerity of Verona, Dept. of Computer Science                   <br>
 *         federico.busato@univr.it
 * @date April, 2017
 * @version v1.3
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
#include "Host/PrintExt.hpp"        //xlib::printArray
#include "Device/SafeCudaAPI.cuh"   //cuMemcpyFromSymbol

namespace cu {

template<class T>
void printArray(const T* d_array, size_t size, const std::string& str, char sep)
                noexcept {
    auto h_array = new T[size];
    cuMemcpyToHost(d_array, size, h_array);
    xlib::printArray(h_array, size, str, sep);
    delete[] h_array;
}

template<class T, int SIZE>
void printArray(const T (&d_array)[SIZE], const std::string& str, char sep)
                noexcept {
    auto h_array = new T[SIZE];
    cuMemcpyFromSymbol(d_array, h_array);

    xlib::printArray(h_array, SIZE, str, sep);
    delete[] h_array;
}

template<class T>
void printSymbol(const T& d_symbol, const std::string& str) noexcept {
    T h_data;
    cuMemcpyFromSymbol(d_symbol, h_data);

    std::cout << str << h_data << std::endl;
}

//------------------------------------------------------------------------------

__device__ __forceinline__
const Cout& operator<<(const Cout& obj, const char* string) noexcept {
    printf("%s", string);
    return obj;
}

__device__ __forceinline__
const Cout& operator<<(const Cout& obj, uint64_t value) noexcept {
    printf("%llu", value);
    return obj;
}

__device__ __forceinline__
const Cout& operator<<(const Cout& obj, int64_t value) noexcept {
    printf("%lld", value);
    return obj;
}

__device__ __forceinline__
const Cout& operator<<(const Cout& obj, long long int value) noexcept {
    printf("%lld", value);
    return obj;
}

__device__ __forceinline__
const Cout& operator<<(const Cout& obj, long long unsigned value)
                             noexcept {
    printf("%llu", value);
    return obj;
}

__device__ __forceinline__
const Cout& operator<<(const Cout& obj, int value) noexcept {
    printf("%d", value);
    return obj;
}

__device__ __forceinline__
const Cout& operator<<(const Cout& obj, unsigned value) noexcept {
    printf("%u", value);
    return obj;
}

__device__ __forceinline__
const Cout& operator<<(const Cout& obj, short value) noexcept {
    printf("%hd", value);
    return obj;
}

__device__ __forceinline__
const Cout& operator<<(const Cout& obj, unsigned short value) noexcept {
    printf("%hu", value);
    return obj;
}

__device__ __forceinline__
const Cout& operator<<(const Cout& obj, char value) noexcept {
    printf("%c", value);
    return obj;
}

__device__ __forceinline__
const Cout& operator<<(const Cout& obj, unsigned char value) noexcept {
    printf("%hhu", value);
    return obj;
}

__device__ __forceinline__
const Cout& operator<<(const Cout& obj, float value) noexcept {
    printf("%f", value);
    return obj;
}

__device__ __forceinline__
const Cout& operator<<(const Cout& obj, double value) noexcept {
    printf("%f", value);
    return obj;
}

template<typename T>
__device__ __forceinline__
typename std::enable_if<std::is_pointer<T>::value, const Cout&>::type
operator<<(const Cout& obj, const T pointer) noexcept {
    printf("0x%llX", pointer);
    return obj;
}

} // namespace cu
