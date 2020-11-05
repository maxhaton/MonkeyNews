/*
    "Scientific" benchmarking: Timing your code over one workload doesn't really cut it any more.
    It should also be possible to easily (where your system allows you to) to measure things like 
    low-level performance counters and memory usage rather than merely time.

    This library attempts to do that, in a nice format that you can use without cluttering your codebase.

    Currently doesn't work with -betterC (yet)
*/
module benchmark;
public import resources;
import configjson;
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
    ///Publish in config file
    Config
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
///This is unique to this mixin so it can be used to find whatever the UDA is attached to.
///
struct BenchmarkKernelImpl(int l, string f, string m)
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
        int l = __LINE__, string f = __FILE__, string m = __MODULE__) //More detailed type checking is done within.
if (validGeneratorRange!rngGenerateParameter)
{
    import std.traits : getSymbolsByUDA, getUDAs;

    //mod is the module we are in
    mixin("import ", m, "; alias mod = ", m, ";");

    alias BenchmarkKernel = BenchmarkKernelImpl!(l, f, m);
    
    alias pack = getSymbolsByUDA!(mod, BenchmarkKernel);
    
    tmpAssert!(pack.length, "Library could not find any functions attached to UDA on: " ~ name) _;
    
    alias theFunction = pack[0];
    pragma(msg, __traits(getAttributes, theFunction));
    auto configStructProto = getUDAs!(theFunction, BenchmarkKernel)[0];

    auto runBenchmark(OutputRange!string outputHere)
    {
        import core.memory : GC;
        void output(string tmp)
        {
            outputHere.put(tmp);
        }
        @trusted static void gcEnableShim()
        {
            GC.enable();
        }

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
            alias ty = typeof(rangeHeader.joiner(";"));
            pragma(msg, ty, ElementType!ty);
            copy(rangeHeader.joiner(";"), outputHere);
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

                
                auto benchmarkOverThis = initializer(indToInd);

                foreach (measure; configStruct.measureBuffer)
                    measure.start();
                //--hot part start
                auto ret = theFunction(benchmarkOverThis, theDataToBenchmarkOver);
                //--hot part end
                foreach (measure; configStruct.measureBuffer)
                    measure.stop();
                //Get the data and store it
                dataBuf[] += configStruct.measureBuffer.map!(that => that.get()).joiner.array()[];

                if (theSettings.putEachMeasurement)
                {
                    //chain([v], dataBuf).map!(x => x.to!string).joiner(";").writeln;
                    outputHere.put(chain([v.to!string], dataBuf.map!(x => x.to!string)).joiner(";"));//.writeln;
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
                outputHere.put(chain([v.to!string], stringedData).joiner(";"));//.writeln;
            }

            indToInd = iterToIter;
        }
    }
    import std.stdio;
    mixin runAtModuleScope!(() => runBenchmark(stdout.lockingTextWriter()), runWhen);
}
//Run in a static constructor or destructor, exceptions are not caught.
template runAtModuleScope(alias what, BenchmarkExecutionPolicy runWhen)
{
    static if (runWhen == BenchmarkExecutionPolicy.Start)
    {
        shared static this()
        {
            what();
        }
    }
    static if (runWhen == BenchmarkExecutionPolicy.End)
    {
        shared static ~this()
        {
            what();
        }
    }
}
//Shim, seems to make deep static asserts actually work
template tmpAssert(bool x, string msg)
{
    static assert(x, msg);
    alias tmpAssert = int;
}