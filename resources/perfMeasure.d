module resources.perfMeasure;
import resources.resroot;
import perf_event;
import core.stdc.stdint;
import core.stdc.stdlib;
import core.sys.posix.sys.ioctl;
import core.sys.posix.unistd;
extern (C) struct read_format
{
    uint64_t nr;
    struct sub_rd
    {
        uint64_t value;
        uint64_t id;
    }

    sub_rd* values;
}

class PerfEvent : ResourceMeasurement
{
    import core.time;

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
    }
    //Memoize file descriptors etc.
    bool config = false;
    int[] fileDescriptors;
    uint64_t[] perf_ids;

    event_tup[] events;
    public override string outputName() pure const
    {
        return "PerfEvent";
    }

    public override final void start()
    {
        //Need to initialize fds. Overhead needs to be measured, but initalization doesn't play well with CTFE
        if (!config)
        {
            foreach (idx, val; events)
            {
                perf_event_attr that;

                memset(&pea, 0, perf_event_attr.sizeof);

                pea.type = val.id;
                pea.size = perf_event_attr.sizeof;
                pea.config = val.eventType;
                pea.disabled = 1;
                pea.exclude_kernel = 1;
                pea.exclude_hv = 1;
                pea.read_format = PERF_FORMAT_GROUP | PERF_FORMAT_ID;

                auto groupFD = idx > 0 ? fileDescriptors[0] : -1;

                auto fd = perf_event_open(&pea, 0, -1, groupFD, 0);

                ioctl(fd, PERF_EVENT_IOC_ID, &perf_ids[idx]);
                fileDescriptors[idx] = fd;
            }
            config = true;
        }

        //Actually start counting

        ioctl(fd, PERF_EVENT_IOC_RESET, PERF_IOC_FLAG_GROUP);
        ioctl(fd, PERF_EVENT_IOC_ENABLE, PERF_IOC_FLAG_GROUP);

    }

    public override final void stop()
    {
        const fd = fileDescriptors[0];
        ioctl(fd1, PERF_EVENT_IOC_DISABLE, PERF_IOC_FLAG_GROUP);
    }

    public override final long get() const pure
    {
        const fd = fileDescriptors[0];
        //Arbitrary buffer size for now
        void[4096] buf;
        read_format* rdPtr = cast(*read_format) &buf[0];
        read(fd, buf, buf.sizeof);
        return rdPtr.values[0].value;
    }
}

