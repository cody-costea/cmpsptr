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
    Ptr!Test ptr = alloc!Test;
    printf("ptr.x = %d\n", ptr.x);
    printf("ptr.sizeof = %d", ptr.sizeof);
    scanf("%d");
    return 0;
}
