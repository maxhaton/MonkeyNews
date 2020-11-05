//Process a config file from monkeynews.json file
module configjson;
import std.json;
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
GenericSettings fromConfig(JSONValue x)
{
    assert(0);
}