module resources.resroot;
import std.range.interfaces;
///
@nogc interface ResourceMeasurement {
    //Don't put impure logic in constructors and destructors
    //GC will not be used for management 

    ///What to lookup in a config file
    static string fullName;
    ///What to print in the output, i.e. Perf_Event(HW_CACHE_MISSES, ...) etc.
    InputRange!string outputHeader() pure const;
    ///Start the measurement
    void start();
    ///Stop measurement and update internal buffer
    void stop();
    ///Give the result of the most recent stopped measurement
    InputRange!ulong get() const;
    ///How many datapoints are outputted.
    int outputCount() const;
}
