///A very simple timer
module resources.timer;

import resources.resroot;
///Timing using the standard library, using the standard clock for whichever system you are on
class PhobosTimer : ResourceMeasurement{
    import core.time;
    static string fullName = "PhobosTimer";
    ///Constructor argument is stringly typed to load from config file
    public this(string unit) {}
    public this() {}
    MonoTime _start = MonoTime.zero();
    MonoTime _end = MonoTime.zero();

    public override string outputName() pure const
    {
        return "PhobosTimer(ns)";
    }
    public override final void start() 
    {
        _start = MonoTime.currTime;
    }
    public override final void stop()
    {   
        _end = MonoTime.currTime();
    }
    public override final long get() const pure
    {
        const dur = _end - _start;
        return dur.total!"nsecs";
    }
}

