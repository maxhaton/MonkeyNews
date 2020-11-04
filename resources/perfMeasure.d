module resources.perfMeasure;
import resources.resroot;
import perf_event;
import core.stdc.stdint;
import core.stdc.stdlib;
import core.sys.posix.sys.ioctl;
import core.sys.posix.unistd;
version(Linux):
extern (C) struct sub_rd
{
    uint64_t value;
    uint64_t id;
}
pragma(msg, sub_rd.sizeof);
extern (C) struct read_format
{
    uint64_t nr;

    sub_rd* values;
}

class PerfEvent : ResourceMeasurement
{
    import core.time;
    import std.range.interfaces;

    static string fullName = "PerfEvent";
    ///Constructor argument is stringly typed to load from config file
    public this(string unit)
    {
    }

    public this()
    {
        events ~= event_tup(perf_type_id.PERF_TYPE_HARDWARE, perf_hw_id.PERF_COUNT_HW_CPU_CYCLES);
        events ~= event_tup(perf_type_id.PERF_TYPE_SOFTWARE, perf_sw_ids.PERF_COUNT_SW_PAGE_FAULTS);

        fileDescriptors = new int[events.length];
        perf_ids = new uint64_t[events.length];
    }

    struct event_tup
    {
        perf_type_id id;
        int eventType;
        string prettyString() const
        {
            import std.conv : to;
            import std.format;

            string eventString;
            switch (id)
            {
            case perf_type_id.PERF_TYPE_HARDWARE:
                perf_hw_id theID = cast(perf_hw_id) eventType;
                eventString = to!string(theID);
                break;
            case perf_type_id.PERF_TYPE_SOFTWARE:
                perf_sw_ids theID = cast(perf_sw_ids) eventType;
                eventString = to!string(theID);
                break;
            default:
                assert(0, "HW and SW only");
            }

            return format!"PerfEvent{%s|%s}"(id.to!string, eventString);
        }

    }
    //Memoize file descriptors etc.
    bool config = false;
    int[] fileDescriptors;
    uint64_t[] perf_ids;

    event_tup[] events;

    public override InputRange!string outputHeader() pure const
    {
        import std.algorithm : map;

        return inputRangeObject(events.map!(x => x.prettyString));
    }

    public override final void start()
    {
        //Need to initialize fds. Overhead needs to be measured, but initalization doesn't play well with CTFE
        if (!config)
        {
            foreach (idx, val; events)
            {
                perf_event_attr pea;
                import core.stdc.string : memset;

                memset(&pea, 0, perf_event_attr.sizeof);

                pea.type = val.id;
                pea.size = perf_event_attr.sizeof;
                pea.config = val.eventType;
                pea.disabled = 1;
                pea.exclude_kernel = 1;
                pea.exclude_hv = 1;
                pea.read_format = perf_event_read_format.PERF_FORMAT_GROUP
                    | perf_event_read_format.PERF_FORMAT_ID;

                auto groupFD = idx > 0 ? fileDescriptors[0] : -1;

                auto fd = perf_event_open(&pea, 0, -1, groupFD, 0);

                ioctl(fd, PERF_EVENT_IOC_ID, &perf_ids[idx]);
                fileDescriptors[idx] = fd;
            }
            config = true;
        }

        //Actually start counting
        const fd = fileDescriptors[0];
        ioctl(fd, PERF_EVENT_IOC_RESET, perf_event_ioc_flags.PERF_IOC_FLAG_GROUP);
        ioctl(fd, PERF_EVENT_IOC_ENABLE, perf_event_ioc_flags.PERF_IOC_FLAG_GROUP);

    }

    public override final void stop()
    {
        const fd = fileDescriptors[0];
        ioctl(fd, PERF_EVENT_IOC_DISABLE, perf_event_ioc_flags.PERF_IOC_FLAG_GROUP);
    }

    public override final InputRange!ulong get() const
    {
        //There's no time constraint here so we can take as long as we want

        import std.stdio;

        const fd = fileDescriptors[0];
        //Arbitrary buffer size for now
        byte[1024] buf;
        buf[] = 0;
        read_format* rdPtr = cast(read_format*)&buf[0];

        read(fd, &buf[0], buf.sizeof);

        const numb = rdPtr.nr;
        //nothings fallen through the cracks
        assert(numb == events.length);
        
        //writeln(cast(uint64_t[]) buf[0..uint64_t.sizeof*3]);
        sub_rd[] data = cast(sub_rd[]) buf[uint64_t.sizeof..(uint64_t.sizeof + sub_rd.sizeof * numb)];
        
        
        return inputRangeObject([data[0].value, data[1].value]);
    }

    public override final int outputCount() const
    {
        return cast(int) events.length;
    }
}
