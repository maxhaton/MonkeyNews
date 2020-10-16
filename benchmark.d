/*
    "Scientific" benchmarking: Timing your code over one workload doesn't really cut it any more.
    It should also be possible to easily (where your system allows you to) to measure things like 
    low-level performance counters and memory usage rather than merely time.

    This library attempts to do that, in a nice format that you can use without cluttering your codebase.

*/
module benchmark;
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
    import std.traits;

    //mod is the module we are in
    mixin("import ", m, "; alias mod = ", m, ";");

    //This is unique to this mixin so it can be used to find whatever the UDA is attached to.
    enum BenchmarkKernel;

    alias pack = getSymbolsByUDA!(mod, BenchmarkKernel);
    pragma(msg, pack);
    alias theFunction = pack[0];

    pragma(msg, "fail");
    auto runBenchmark()
    {
        foreach (v; rngGenerateParameter)
        {
            import std.datetime.stopwatch;
            import std.stdio;
            auto x = new LinkedList();
            const tmp = parameterToData(v);

            

            auto sw = StopWatch(AutoStart.no);
            sw.start();
            auto ret = theFunction(x, tmp);
            sw.stop();

            
            long nsecs = sw.peek.total!"nsecs";
            writeln(v,",",nsecs);
            
        }
    }

    shared static this()
    {
        import std.stdio;

        writeln("Running: ", name);
        runBenchmark();

    }
}
