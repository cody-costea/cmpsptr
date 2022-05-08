module APP;
import core.stdc.stdio;
import cmpsptr;

struct Test
{
    public static SNr[3] testArr = [9, 8, 7];

    SNr x = 3;

    ~this()
    {        
        printf("test destructor!\n");
    }
}

void testFunc(Ptr!(Test, 1) tst, const UNr again)
{
    printf("tst.count = %d\n", (tst.refCount));
    if (again < 3)
    {
        testFunc(tst, again + 1);
    }
}

extern (C) int main(string[] args) {        
    Test* ptr = alloc!Test;
    ptr.x = 7;
    printf("ptr.x = %d\n", ptr.x);
    printf("ptr.sizeof = %d\n", ptr.sizeof);
    Ptr!(Test, -1) tst = ptr;
    //printf("tst.count = %d\n", (tst.refCount));
    //testFunc(tst, 0);
    printf("tst.x = %d\n", tst.x);
    tst.x = 1;
    printf("tst.x = %d\n", tst.x);
    printf("tst.sizeof = %d\n", tst.sizeof);
    Hnl!("APP.Test.testArr", "APP") testArr = 2;
    SNr testArrElm = testArr;
    printf("testArr = %d\n", testArrElm);
    //printf("tst.count = %d\n", (tst.refCount));
    //scanf("%d");
    return 0;
}
