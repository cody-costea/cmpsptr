module APP;
import core.stdc.stdio;
import cmpsptr;

struct Test
{
    public static const SNr[3] testArr = [9, 8, 7];

    SNr x = 3;

    this(const SNr x)
    {
        this.x = x;
    }

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

void testHndlFunc(Hnl!("APP.Test.testArr", "APP") tst)
{
    printf("APP.Test.testArr.index = %d\n", (tst.index));
    printf("APP.Test.testArr.sizeof = %d\n", (tst.sizeof));
}

extern (C) int main(string[] args) {        
    Test* ptr = allocNew!Test(5);
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
    //Hnl!("APP.Test.testArr", "APP") testArr = 2;
    Hnl!("APP.Test.testArr", "APP") testArr = &(APP.Test.testArr[2]);
    testHndlFunc(testArr);
    SNr testArrElm = testArr;
    printf("testArr = %d\n", testArrElm);
    //printf("tst.count = %d\n", (tst.refCount));
    //scanf("%d");
    return 0;
}
