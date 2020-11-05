module proc;
import std;
import core.sys.linux.unistd;

extern(C) void *sbrk(intptr_t increment);
uint major(dev_t dev)
{
	return cast(uint) (((dev) >> 16) & 0xffff);
}
uint minor(dev_t dev)
{
	return cast(uint) ((dev) & 0xffff);
}

dev_t makedev(uint maj, uint min)
{
    static assert(dev_t.sizeof == 2*uint.sizeof);
	return (((maj) << 16) | ((min) & 0xffff));
}
const struct ProcMapsEntry { 
    static assert((void*).sizeof == size_t.sizeof);
    void* start, end;
    immutable(char[4]) permissions;
    off_t offset;
    dev_t device;
    ino_t inode;
    string theRest;
    
    this(T)(T x)
        if(isSomeString!T)
    {
        string perm, rest;
        //Ugly hack because std.format doesn't like pointers
        size_t ptr1, ptr2;

        off_t offsetset;
        ino_t setTo;
        uint devmajor, devminor;
        const cnt = formattedRead!"%x-%x %s %x %x:%x %d %s"(x, ptr1, ptr2, perm, offsetset, devmajor, devminor, setTo, rest);

        start = cast(immutable void*) ptr1;
        end = cast(immutable void*) ptr2;

        assert(perm.length == 4);
        permissions = perm;

        offset = offsetset;
        inode = setTo;

        device = makedev(devmajor, devminor);

        theRest = rest;
    }

    size_t size()
    {
        return end - start;
    }
}
///
auto getFromPID(pid_t pid = getpid())
{
    auto f = File(format!"/proc/%d/maps"(pid), "r");
    //f.byLine.map!(str => ProcMapsEntry(str)).find!(tmp => tmp.rest == "[heap]").take(1).front.size;
    return f.byLine.map!(str => ProcMapsEntry(str));
}


