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
import std.algorithm, std.traits, std.range, std.stdio : writeln;

/*
    Declare when your benchmark will actually be run. 
*/
enum BenchmarkExecutionPolicy
{
    ///Run at the start of module loading
    Start = 0,
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

///Generic settings seperated from the benchmark specific configuration struct for reuse.
struct GenericSettings
{
    //This does not use bitflags currently because it's not important and going to be CTFE'd

    ///How many iterations
    uint iterations = 3;
    ///Dump each measurement individually rather than taking the mean
    bool putEachMeasurement = false;
    /++
        Attempt to flush the cachce of newly minted memory between independant variable measurements
        i.e. if you take a large number of measurement you can see how hot or cold caches effect it.
    +/
    bool flushCache = false;
    ///Allow the garbage collector to run as normal
    bool enableGC = true;
    ///Force a collection on each independant measurement
    bool collectOnIndependant = true;
    ///Force a collection on each iteration
    bool collectOnIteration = true;
    this(uint iters)
    {
        iterations = iters;
    }
}
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
    //Will eventually rely upon uprobes, most likely.
    
}
///Is it a valid generator of an independant variable to benchmark against, i.e. an input range of element type convertible with size_t
template validGeneratorRange(alias input)
{
    import std.traits;

    static if (isSomeFunction!input)
    {
        alias Rty = ReturnType!input;
        enum validGeneratorRange = isInputRange!ty
            && isImplicitlyConvertible!(ElementType!ty, size_t);
    }
    else
    {
        alias ty = typeof(input);
        enum validGeneratorRange = isInputRange!ty
            && isImplicitlyConvertible!(ElementType!ty, size_t);
    }
}

/++
   Use this UDA to declare a benchmark kernel - this will automatically be scheduled and run 
   by the library, over the range of values specified. 

   If you want to pass multiple parameters, pack them in a tuple.

   This is intended for measuring (and/or verifying) the performance of an algorithm or data structure
   over some range of values of *any* statistic. You have to generate the statistic yourself unfortunately,
   but it can work out what you want to measure for you.

   Currently this will only look at top (module decl) level scope, to avoid compile time slow down searching.

   After instantiating a BenchmarkKernel, it aliases to a configuration structure that you can put your resource 
   measurement classes (It's less efficient to use OOP here, but much simpler than using a tagged union at this stage) here 
   using it's constructor.

   Do not interfere with the final arguments (m (module), l (line)), if you change these it will not be able to find your function.
   Also, if you make a mistake this library will often complain fairly quietly due to the idiosyncrasies of D's template error messages. 

   Params:
        name = Give your benchmark a nice name
        rngGenerateParameters = Generate the parameter set you want to test over
        parameterToData = The previous parameter specifies how the parameter is generated, this turns that
                            parameter into a dataset to give to your benchmark
        initializer = Initialize the thing you are going to benchmark, before it gets the data, the first parameter is a pointer to
                        result of the last run (not iteration). Feel free to ignore it, if you don't the first parameter must be const
                        (just add const to your lambda before the name). The functionality works with a proper function too.
        runWhen = Use the enum BenchmarkExecutionPolicy to set when the benchmark is run, defaults to deferred execution. This cannot 
                    be done in the config struct due to the (either GC or otherwise) allocation of the resource measurement types
    
 +/
template BenchmarkKernel(string name, alias rngGenerateParameter, alias parameterToData, alias initializer,
        BenchmarkExecutionPolicy runWhen = BenchmarkExecutionPolicy.Defer,
        int l = __LINE__, string m = __MODULE__) //More detailed type checking is done within.
if (validGeneratorRange!rngGenerateParameter)
{
    import std.traits : getSymbolsByUDA, getUDAs;

    //mod is the module we are in
    mixin("import ", m, "; alias mod = ", m, ";");

    ///This is unique to this mixin so it can be used to find whatever the UDA is attached to.
    ///
    struct BenchmarkKernel
    {
        ResourceMeasurement[] measureBuffer;
        GenericSettings settings;
        Visibility type;
        ///
        this(typeof(type) setvis, typeof(settings) setsets, ResourceMeasurement[] measures...)
        {
            type = setvis;
            measureBuffer = measures;
            settings = setsets;
        }

        @trusted ~this()
        {
            if (__ctfe)
            {
                //Ensure deterministic destruction, structs are too complicated here but the GC cannot be relied upon
                foreach (meas; measureBuffer)
                    destroy(meas);
            }
        }
    }

    alias pack = getSymbolsByUDA!(mod, BenchmarkKernel);
    //Static assert failures don't work 
    static if (pack.length == 0)
        pragma(msg, "Benchmark setup at ", m, ":", l,
                " failed. Library could not find your function. \nDMD suppresses failures in templates like these.");

    alias theFunction = pack[0];
    auto configStructProto = getUDAs!(theFunction, BenchmarkKernel)[0];

    auto runBenchmark()
    {
        import core.memory : GC;

        @trusted void gcEnableShim() {GC.enable();}
        

        //Turn the GC back on in case a benchmark turned it off downstairs
        scope (exit)
            gcEnableShim();
        auto configStruct = configStructProto;

        const GenericSettings theSettings = configStruct.settings;

        //Get function parameters
        alias params = Parameters!theFunction;
        //pragma(msg, params);
        //The type the benchmark is run on
        alias BenchType = params[0];
        //Pointer from results of independant variable to next
        BenchType* indToInd = null;


        //Lambdas are tempaltes by default
        static if (__traits(isTemplate, initializer))
            alias inst = initializer!(BenchType*);
        else //No instantiation needed, not a template
            alias inst = initializer;
        //Make sure the initializer works properly
        static assert(__traits(compiles, inst(indToInd)));
        
        

        static assert(is(Parameters!inst[0] : const BenchType*));
        //Print a nice header
        {
            auto rangeHeader = chain(["N"],
                    configStruct.measureBuffer.map!(x => x.outputHeader()).joiner());

            rangeHeader.joiner(";").writeln;
        }

        foreach (v; rngGenerateParameter)
        {
            BenchType* iterToIter = null;
            if (theSettings.enableGC)
            {
                if (theSettings.collectOnIndependant)
                    GC.collect();
            }
            else
            {
                GC.disable();
            }
            import std.conv : to;
            import core.stdc.stdlib : alloca;

            //Get return type of parameter generation
            const theDataToBenchmarkOver = parameterToData(v);
            alias benchInputType = typeof(theDataToBenchmarkOver);

            /*
                Counters are generic input ranges, so we sum over their lengths to find the number
                of counters they will give to us.
            */
            const bufLen = configStruct.measureBuffer.map!(x => x.outputCount).sum();

            //Allocated on the stack mainly because we can - avoiding GC for now should make it easier to be -betterC later.
            ulong[] dataBuf = (cast(ulong*) alloca(bufLen * ulong.sizeof))[0 .. bufLen];
            //No unitialized stack memory please
            dataBuf[] = 0;
            //Ideally we would do all iterations in one go and measure the lot but this is easier said than done 
            //largely due to compiler optimizations i.e. if the function has no sideeffects
            foreach (itercnt; 0 .. theSettings.iterations)
            {
                if (theSettings.enableGC)
                    if (theSettings.collectOnIteration)
                        GC.collect();

                //GC disabled, but present

                auto benchmarkOverThis = initializer(indToInd);

                foreach (measure; configStruct.measureBuffer)
                    measure.start();
                //--hot part start
                auto ret = theFunction(benchmarkOverThis, theDataToBenchmarkOver);
                //--hot part end
                foreach (measure; configStruct.measureBuffer)
                    measure.stop();

                uint idx = 0;
                foreach (vg; configStruct.measureBuffer)
                {
                    auto data = vg.get();
                    foreach (val; data)
                    {
                        dataBuf[idx] += val;
                        ++idx;
                    }
                }

                if (theSettings.putEachMeasurement)
                {
                    //chain([v], dataBuf).map!(x => x.to!string).joiner(";").writeln;
                    chain([v.to!string], dataBuf.map!(x => x.to!string)).joiner(";").writeln;
                    dataBuf[] = 0;
                }

                //Keep track of iteration pointer
                iterToIter = &benchmarkOverThis;
            }
            //Print meaned results to an output range
            if (!theSettings.putEachMeasurement)
            {
                auto stringedData = dataBuf.map!(x => (cast(float) x) / theSettings.iterations)
                    .map!(f => f.to!string);
                chain([v.to!string], stringedData).joiner(";").writeln;
            }

            indToInd = iterToIter;
        }
    }

    mixin runAtModuleScope!(runBenchmark, runWhen);
}

template runAtModuleScope(alias what, BenchmarkExecutionPolicy runWhen)
{
    static if (runWhen == BenchmarkExecutionPolicy.Start)
    {
        shared static this()
        {
            try
            {
                what();
            }
            catch (Error e)
            {
                e.msg.writeln;
                e.info.writeln;
            }
        }
    }
    static if (runWhen == BenchmarkExecutionPolicy.End)
    {
        shared static ~this()
        {
            try
            {
                what();
            }
            catch (Error e)
            {
                e.msg.writeln;
                e.info.writeln;
            }
        }
    }
}


