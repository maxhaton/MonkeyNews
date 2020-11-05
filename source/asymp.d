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