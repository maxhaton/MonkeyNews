/*
    "Scientific" benchmarking: Timing your code over one workload doesn't really cut it any more.
    It should also be possible to easily (where your system allows you to) to measure things like 
    low-level performance counters and memory usage rather than merely time.

    This library attempts to do that, in a nice format that you can use without cluttering your codebase.

    Currently doesn't work with -betterC (yet)
*/
module benchmark;
public import resources;
import resources.resroot;

///The resource to measure, strings here are what is looked for in a config file
public enum ResourceMeasurementType : string
{
    ///
    time = "time",
    ///
    perf_event = "perf_event_open"
}

/*
    Declare when your benchmark will actually be run. 
*/
enum BenchmarkExecutionPolicy
{
    ///Run at the start of module loading
    Start,
    ///Run when module leaves scope
    End,
    //Look for a config file and run only when that file is found.
    Defer
}

enum Visibility
{
    ///Do not publish
    Hidden,

    Config
}
///
enum ContainsBenchmarks;

/++
   Use this to declare the resource profile of your operation.

   These must be templates for inference to work.

   This distinguishes between asymptotic and amortized performance. For example, if you consider a managed dynamic array,
   a good one will reallocate a certain ratio of memory more than it needs to save time for it's next operation, so pushing back 
   to end end of the array will most likely be O(1) rather than O(n), whereas the asymptotic upper bound for the operation 
   in general is O(n).

   Params:
        BigOPerformanceTemplate = Use this to specify the Asymptotic lower bound on resource use
        AmortizedPerformanceTemplate = Use this to declare the amortized performance of the operation
 +/
template ResourceCurve(alias BigOPerformanceTemplate, alias AmortizedPerformanceTemplate)
{

}
/++
   Use this UDA to declare a benchmark kernel - this will automatically be scheduled and run 
   by the library, over the range of values specified. 

   If you want to pass multiple parameters, pack them in a tuple.

   This is intended for measuring (and/or verifying) the performance of an algorithm or data structure
   over some range of values of *any* statistic. You have to generate the statistic yourself unfortunately,
   but it can work out what you want to measure for you.

   Currently this will only look at top (module decl) level scope, to avoid compile time slow down searching. If you want it to search
   your scope for benchmarks use the @ContainsBenchmarks UDA to tell it where to look.

   Do not interfere with the __m (module), __l (line), if you change these it will not be able to find your function.

   The library provides mechanisms to stop the compiler optimizing certain things away so your data is valid.
   Params:
        name = Give your benchmark a nice name
        rngGenerateParameters = Generate the parameter set you want to test over
        parameterToData = The previous parameter specifies how the parameter is generated, this turns that
                            parameter into a dataset to give to your benchmark

    
 +/
template BenchmarkKernel(string name, alias rngGenerateParameter,
        alias parameterToData, int l = __LINE__, string m = __MODULE__)
{
    import std.traits : getSymbolsByUDA, getUDAs;

    //mod is the module we are in
    mixin("import ", m, "; alias mod = ", m, ";");

    ///This is unique to this mixin so it can be used to find whatever the UDA is attached to.
    ///
    struct BenchmarkKernel
    {
        ResourceMeasurement[] measureBuffer;
        ///
        BenchmarkExecutionPolicy type;
        ///
        this(typeof(type) set, ResourceMeasurement[] measures...)
        {
            type = set;
            measureBuffer = measures;
        }
        ~this()
        {
            if(__ctfe) {
                //Ensure deterministic destruction, structs are too complicated here but the GC cannot be relied upon
                foreach(meas; measureBuffer)
                    destroy(meas);
            }
        }
    }

    alias pack = getSymbolsByUDA!(mod, BenchmarkKernel);
    static assert(pack.length == 1);

    alias theFunction = pack[0];
    auto configStructProto = getUDAs!(theFunction, BenchmarkKernel)[0];
    //pragma(msg, configStructProto);
    version (PrintBenchmarkNames)
    {
        pragma(msg, "Benchmarking -> ", fullyQualifiedName!theFunction, " i.e. ", name);
    }
    auto runBenchmark()
    {
        auto configStruct = configStructProto;
        //Print a nice header
        {
            import std.algorithm, std.range, std.stdio : writeln;

            chain(["N"], configStruct.measureBuffer.map!(x => x.outputName)).joiner(";").writeln;
        }
        foreach (v; rngGenerateParameter)
        {
            import std.datetime.stopwatch;
            import std.stdio, std.algorithm, std.range, std.conv : to;
            import std.traits;
            
            import core.stdc.stdlib : alloca;
            //Get return type of parameter generation
            const theDataToBenchmarkOver = parameterToData(v);
            alias benchInputType = typeof(theDataToBenchmarkOver);

            //Get function parameters
            alias params = Parameters!theFunction;
            pragma(msg, params);

            auto x = new LinkedList();

            auto sw = StopWatch(AutoStart.no);

            foreach (measure; configStruct.measureBuffer)
                measure.start();

            auto ret = theFunction(x, theDataToBenchmarkOver);

            foreach (measure; configStruct.measureBuffer)
                measure.stop();


            //Data is currently not saved, to avoid the GC.
            const bufLen = configStruct.measureBuffer.length;
            long[] dataBuf = (cast(long*) alloca(bufLen * long.sizeof))[0..bufLen];
            dataBuf[] = configStruct.measureBuffer.map!(x => x.get).array()[];
            //Print results to an output range
            chain([v], dataBuf).map!(x => x.to!string).joiner(";").writeln;

        }
    }

    shared static this()
    {
        import std.stdio;

        writeln("Running: ", name);
        runBenchmark();

    }
}
