package test;

import junit.framework.Test;
import junit.framework.TestCase;
import junit.framework.TestSuite;
import test.Zap;

/**
 * Unit test for simple App.
 */
public class AppTest
    extends TestCase
{
    /**
     * Create the test case
     *
     * @param testName name of the test case
     */
    public AppTest( String testName )
    {
        super( testName );
    }

    /**
     * @return the suite of tests being tested
     */
    public static Test suite()
    {
        return new TestSuite( AppTest.class );
    }

    /**
     * Rigourous Test :-)
     */
    public void testApp() {
        int a = 1 / 0;
        assertTrue("Rigourous Test.", true );
    }

    public void testApp1() {
        Zap zap = new Zap();
        zap.doPlunk();
        assertEquals("Rigourous Test1.", 1, 0);
    }

    public void testApp2() {
        assertEquals("Rigourous Test2.", 3, 0);
    }

}
