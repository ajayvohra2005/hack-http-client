namespace HackHttp\Tests\Client\CookieJar;

use HackHttp\Tests\Helper;

use HackHttp\Client\Cookie\FileCookieJar;
use HackHttp\Client\Cookie\SetCookie;
use function Facebook\FBExpect\expect;
use type Facebook\HackTest\{HackTest,DataProvider};

/**
 * @covers HackTest\Client\Cookie\FileCookieJar
 */
class FileCookieJarTest extends HackTest
{


    public function testPersistsToFile(): void
    {
        $file = \tempnam(\sys_get_temp_dir(), 'file-cookies');
        $jar = new FileCookieJar($file);
        $jar->setCookie(new SetCookie(dict[
            'Name'    => 'foo',
            'Value'   => 'bar',
            'Domain'  => 'foo.com',
            'Expires' => \time() + 1000
        ]));
        $jar->setCookie(new SetCookie( dict[
            'Name'    => 'baz',
            'Value'   => 'bar',
            'Domain'  => 'foo.com',
            'Expires' => \time() + 1000
        ]));
        $jar->setCookie(new SetCookie( dict[
            'Name'    => 'boo',
            'Value'   => 'bar',
            'Domain'  => 'foo.com',
        ]));

        expect($jar->count())->toBeSame(3);

        $jar->save();
    

        // Make sure it wrote to the file
        $contents = \file_get_contents($file);
        Helper::assertNotEmpty($contents);
    }

}
