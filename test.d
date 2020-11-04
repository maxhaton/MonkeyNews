module test;
import benchmark;
import std;
//A simple example of a datastructure we love to hate
class LinkedList {
    class Node {
        int data;
        this(int tmp) pure
        {
            data = tmp;
        }
        Node next;
    }

    Node root;


    this(int start)
    {
        root = new Node(start);
    }
    this()
    {
        
    }

    size_t length() const
    {
        static lengthHelper(size_t x, const Node inp)
        {
            if(inp is null)
                return x;
            else 
                return lengthHelper(x + 1, inp.next);
        }
        
        return lengthHelper(0, root);
    }
    void insertFront(int x) pure
    {
        if(root is null) {
            root = new Node(x);
            return;
        }

        auto insertThis = new Node(x);
        insertThis.next = this.root;
        
        root = insertThis;
    }
    
    ref auto opIndex(size_t index) {
        Node cur = root;
        size_t cnt = 0;
        while(index != cnt)
        {
            assert(cur.next);
            cur = cur.next;

            cnt += 1;
        }
    }
}
//Generate random n random numbers
alias rng = (n) => generate!(() => uniform(int.min, int.max)).takeExactly(n).array;
import resources.timer;
import resources.perfMeasure;


@BenchmarkKernel!("Linked List insert benchmark", iota(1, 100), rng, (const _) => new LinkedList(), BenchmarkExecutionPolicy.Start)(Visibility.Config, GenericSettings(300), new PhobosTimer)
auto benchOperation(LinkedList input, inout int[] data) pure
{
    foreach(x; data)
        input.insertFront(x);
    return input;
}

int main()
{
    import std;
    auto myList = new LinkedList(0);
    iota(1, 100).each!(x => myList.insertFront(x));
    //myList.length.writeln;
    return 0;
}