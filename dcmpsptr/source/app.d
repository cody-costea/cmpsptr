import core.stdc.stdio;
import cmpsptr;

struct Test
{
    SNr x = 3;

    ~this()
    {        
        printf("test destructor!");
    }
}

extern (C) int main(string[] args) {        
    Test* ptr = alloc!Test;
    ptr.x = 7;
    printf("ptr.x = %d\n", ptr.x);
    printf("ptr.sizeof = %d\n", ptr.sizeof);
    Ptr!Test tst = ptr;
    printf("tst.x = %d\n", tst.x);
    printf("tst.sizeof = %d\n", tst.sizeof);
    //scanf("%d");
    return 0;
}
