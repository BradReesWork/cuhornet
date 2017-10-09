#pragma once

#include "Host/Metaprogramming.hpp"                 //xlib::SelectType
#include "Device/VectorUtil.cuh"                    //xlib::Make2Str
#include "Core/MemoryManager/MemoryManagerConf.hpp" //EDGES_PER_BLOCKARRAY
#include <tuple>                                    //std::tuple

namespace hornet {

/**
 * @brief vertex id type
 * @remark `id_t` must be *integral* type
 */
using vid_t = int;

/**
 * @brief offset type
 * @remark `offset_t` must be *integral* type
 */
using eoff_t = int;

//==============================================================================
//==============================================================================

using xlib::byte_t;
using degree_t = vid_t;
using   off2_t = typename xlib::Make2Str<eoff_t>::type;
using   vid2_t = typename xlib::Make2Str<vid_t>::type;
using idpair_t = vid2_t;

/**
 * @brief
 */
template<typename... TArgs>
using TypeList = std::tuple<TArgs...>;

/**
 * @brief
 */
using    EMPTY = std::tuple<>;

using  EnableT = std::nullptr_t;

template<int INDEX, int NUM_TYPES, typename... TArgs>
using IndexT = typename std::conditional<(INDEX >= NUM_TYPES), EnableT,
               typename xlib::SelectType<(INDEX < NUM_TYPES ? INDEX : 0)>::type
               >::type;

template<typename... EdgeTypes>
const size_t PITCH = EDGES_PER_BLOCKARRAY *
                     xlib::MaxSize<vid_t, EdgeTypes...>::value;

namespace gpu {
    template<typename, typename>
    class Hornet;
}

namespace csr {
    template<typename, typename>
    class Hornet;
}

template<typename>
class IsHornet : public std::false_type {};

template<typename T, typename R>
class IsHornet<gpu::Hornet<T, R>> : public std::true_type {};

template<typename T, typename R>
class IsHornet<csr::Hornet<T, R>> : public std::true_type {};

} // namespace hornet
