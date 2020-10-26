module resources.resroot;
///
@nogc interface ResourceMeasurement {
    //Don't put impure logic in constructors and destructors


    ///What to lookup in a config file
    static string fullName;
    ///What to print in the output, i.e. Perf_Event(HW_CACHE_MISSES, ...) etc.
    string outputName() pure const;
    ///Start the measurement
    void start();
    ///Stop measurement and update internal buffer
    void stop();
    ///Give the result of the most recent stopped measurement
    long get() pure const;
}
