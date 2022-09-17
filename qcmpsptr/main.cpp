#include <QDebug>
#include <QCoreApplication>

#include "cmpsptr.hpp"

using namespace cmpsptr;

#if ALIGN_POINTERS
inline void* operator new(const std::size_t size, std::nothrow_t)
{
    return globalNew(size, std::nothrow);
}

void* operator new(const std::size_t size)
{
    return globalNew(size);
}

void operator delete(void* ptr) noexcept
{
    clear(ptr);
}
#endif

class FirstTest
{
public:
    int a = 7;

    inline FirstTest()
    {
        qDebug() << "FirstTest constructor test!";
    }

    inline ~FirstTest()
    {
        qDebug() << "FirstTest destructor test!";
    }
};

class SecondTest
{
public:
    int b = 3;

    CmpsPtr<FirstTest, -1> firstTestPtr;

    inline SecondTest() : firstTestPtr(new FirstTest)
    {
        qDebug() << "SecondTest constructor test!";
    }

    inline ~SecondTest()
    {
        qDebug() << "SecondTest destructor test!";
    }
};

class ThirdTest
{
public:
    int c = 1;

    CmpsPtr<SecondTest, 1> secondTestPtr;

    inline ThirdTest() : secondTestPtr(new SecondTest)
    {
        qDebug() << "ThirdTest constructor test!";
    }

    inline ~ThirdTest()
    {
        qDebug() << "ThirdTest destructor test!";
    }
};

void testFunc2(CmpsCnt<ThirdTest> thirdTest)
{
    qDebug() << "sizeof(thirdTest) = " << sizeof(thirdTest);
    qDebug() << "thirdTestPtr->c = " << thirdTest->c;
}

void testFunc(CmpsCnt<ThirdTest> thirdTest)
{
    qDebug() << "sizeof(secondTestPtr) = " << sizeof(thirdTest->secondTestPtr);
    qDebug() << "firstTestPtr->a = " << thirdTest->secondTestPtr->firstTestPtr->a;
    qDebug() << "secondTestPtr->b = " << thirdTest->secondTestPtr->b;
    testFunc2(thirdTest);
}

int main(int argc, char *argv[])
{
    //QCoreApplication a(argc, argv);
    CmpsCnt<ThirdTest> thirdTest(new ThirdTest);
    testFunc(thirdTest);
    //return a.exec();
}
