/**
 * @author Federico Busato                                                  <br>
 *         Univerity of Verona, Dept. of Computer Science                   <br>
 *         federico.busato@univr.it
 * @date April, 2017
 * @version v1.3
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
#include <cmath>            //std::sqrt
#include <ctime>            //std::clock
#include <iomanip>          //std::setprecision
#include <ratio>            //std::ratio
#if defined(__linux__)
    #include <sys/times.h>  //::times
    #include <unistd.h>     //::sysconf
#endif

namespace timer {

template<class Rep, std::intmax_t Num, std::intmax_t Denom>
std::ostream& operator<<(std::ostream& os,
                         const std::chrono::duration
                            <Rep, std::ratio<Num, Denom>>&) {
    if (Num == 3600 && Denom == 1)  return os << " h";
    if (Num == 60 && Denom == 1)    return os << " min";
    if (Num == 1 && Denom == 1)     return os << " s";
    if (Num == 1 && Denom == 1000)  return os << " ms";
    return os << " Unsupported";
}

//==============================================================================
//-------------------------- GENERIC -------------------------------------------

template<timer_type type, typename ChronoPrecision>
TimerBase<type, ChronoPrecision>
::TimerBase(int decimals, int space, xlib::Color color) :
                   _decimals(decimals),
                   _space(space),
                   _default_color(color) {}

template<timer_type type, typename ChronoPrecision>
float TimerBase<type, ChronoPrecision>::duration() const {
    return _time_elapsed.count();
}

template<timer_type type, typename ChronoPrecision>
float TimerBase<type, ChronoPrecision>::total_duration() const {
    return _total_time_elapsed.count();
}

template<timer_type type, typename ChronoPrecision>
float TimerBase<type, ChronoPrecision>::average() const {
    auto num_executions = static_cast<float>(_num_executions);
    return _total_time_elapsed.count() / num_executions;
}

template<timer_type type, typename ChronoPrecision>
float TimerBase<type, ChronoPrecision>::std_deviation() const {
    auto term1 = _num_executions * _time_squared.count();
    auto term2 = _total_time_elapsed.count() * _total_time_elapsed.count();
    return std::sqrt(term1 - term2) / _num_executions;
}

template<timer_type type, typename ChronoPrecision>
void TimerBase<type, ChronoPrecision>::print(const std::string& str)    //NOLINT
                                                            const {
    xlib::IosFlagSaver tmp;
    std::cout << _default_color
              << std::right << std::setw(_space - 2) << str << "  "
              << std::fixed << std::setprecision(_decimals)
              << duration() << ChronoPrecision() << xlib::Color::FG_DEFAULT
              << std::endl;
}

//==============================================================================
//-----------------------  HOST ------------------------------------------------

template<typename ChronoPrecision>
inline Timer<HOST, ChronoPrecision>::Timer(int decimals, int space,
                                           xlib::Color color) :
        TimerBase<HOST, ChronoPrecision>(decimals, space, color) {}

template<typename ChronoPrecision>
inline void Timer<HOST, ChronoPrecision>::start() {
    assert(!_start_flag);
    _start_time = std::chrono::system_clock::now();
    assert(_start_flag = true);
}

template<typename ChronoPrecision>
inline void Timer<HOST, ChronoPrecision>::stop() {
    assert(_start_flag);
    _stop_time     = std::chrono::system_clock::now();
    _time_elapsed  = ChronoPrecision(_stop_time - _start_time);
    _time_squared += _time_elapsed * _time_elapsed.count();
    _total_time_elapsed += _time_elapsed;
    _num_executions++;
    assert(!(_start_flag = false));
}

//==============================================================================
//-------------------------- CPU -----------------------------------------------

template<typename ChronoPrecision>
inline Timer<CPU, ChronoPrecision>::Timer(int decimals, int space,
                                          xlib::Color color) :
        TimerBase<CPU, ChronoPrecision>(decimals, space, color) {}

template<typename ChronoPrecision>
inline void Timer<CPU, ChronoPrecision>::start() {
    assert(!_start_flag);
    _start_clock = std::clock();
    assert(_start_flag = true);
}

template<typename ChronoPrecision>
inline void Timer<CPU, ChronoPrecision>::stop() {
    assert(_start_flag);
    _stop_clock = std::clock();
    auto clock_time_elapsed = static_cast<float>(_stop_clock - _start_clock) /
                              static_cast<float>(CLOCKS_PER_SEC);
    auto time_seconds = seconds(clock_time_elapsed);
    _time_elapsed  = std::chrono::duration_cast<ChronoPrecision>(time_seconds);
    _time_squared += _time_elapsed * _time_elapsed.count();
    _total_time_elapsed += _time_elapsed;
    _num_executions++;
    assert(!(_start_flag = false));
}

//==============================================================================
//-------------------------- SYS -----------------------------------------------

#if defined(__linux__)

template<typename ChronoPrecision>
inline Timer<SYS, ChronoPrecision>::Timer(int decimals, int space,
                                          xlib::Color color) :
        TimerBase<SYS, ChronoPrecision>(decimals, space, color) {}

template<typename ChronoPrecision>
inline void Timer<SYS, ChronoPrecision>::start() {
    assert(!_start_flag);
    _start_time = std::chrono::system_clock::now();
    ::times(&_start_TMS);
    assert(_start_flag = true);
}

template<typename ChronoPrecision>
inline void Timer<SYS, ChronoPrecision>::stop() {
    assert(_start_flag);
    _stop_time = std::chrono::system_clock::now();
    ::times(&_end_TMS);
    assert(!(_start_flag = false));
}

template<typename ChronoPrecision>
inline void Timer<SYS, ChronoPrecision>::print(const std::string& str)  //NOLINT
                                                               const {
    xlib::IosFlagSaver tmp;
    auto  wall_time_ms = std::chrono::duration_cast<ChronoPrecision>(
                                             _stop_time - _start_time ).count();

    auto     user_diff = _end_TMS.tms_utime - _start_TMS.tms_utime;
    auto    user_float = static_cast<float>(user_diff) /
                         static_cast<float>(::sysconf(_SC_CLK_TCK));
    auto     user_time = seconds(user_float);
    auto  user_time_ms = std::chrono::duration_cast<ChronoPrecision>(user_time);

    auto      sys_diff = _end_TMS.tms_stime - _start_TMS.tms_stime;
    auto     sys_float = static_cast<float>(sys_diff) /
                         static_cast<float>(::sysconf(_SC_CLK_TCK));
    auto      sys_time = seconds(sys_float);
    auto   sys_time_ms = std::chrono::duration_cast<ChronoPrecision>(sys_time);

    std::cout << _default_color << std::setw(_space) << str
              << std::fixed << std::setprecision(_decimals)
              << "  Elapsed time: [user " << user_time_ms << ", system "
              << sys_time_ms << ", real "
              << wall_time_ms << ChronoPrecision() << "]"
              << xlib::Color::FG_DEFAULT << std::endl;
}
#endif

//==============================================================================
//-------------------------- CUDA ----------------------------------------------

//#if defined(__NVCC__)

template<typename ChronoPrecision>
Timer<DEVICE, ChronoPrecision>
::Timer(int decimals, int space, xlib::Color color) :
                    TimerBase<DEVICE, ChronoPrecision>(decimals, space, color) {
    cudaEventCreate(&_start_event);
    cudaEventCreate(&_stop_event);
}

template<typename ChronoPrecision>
Timer<DEVICE, ChronoPrecision>::~Timer() {
    cudaEventDestroy(_start_event);
    cudaEventDestroy(_stop_event);
}

template<typename ChronoPrecision>
void Timer<DEVICE, ChronoPrecision>::start() {
    assert(!_start_flag);
    cudaEventRecord(_start_event, 0);
    assert(_start_flag = true);
}

template<typename ChronoPrecision>
void Timer<DEVICE, ChronoPrecision>::stop() {
    assert(_start_flag);
    cudaEventRecord(_stop_event, 0);
    cudaEventSynchronize(_stop_event);
    float cuda_time_elapsed;
    cudaEventElapsedTime(&cuda_time_elapsed, _start_event, _stop_event);
    _time_elapsed  = ChronoPrecision(cuda_time_elapsed);
    _time_squared += _time_elapsed * _time_elapsed.count();
    _total_time_elapsed += _time_elapsed;
    _num_executions++;
    assert(!(_start_flag = false));
}

//#endif

} // namespace timer
