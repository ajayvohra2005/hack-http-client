namespace HackHttp\Tests\Client\CookieJar;

use HackHttp\Tests\Helper;

use namespace HH\Lib\Str;
use namespace HH\Lib\Vec;

use HackHttp\Client\Cookie\SetCookie;
use function Facebook\FBExpect\expect;
use type Facebook\HackTest\{HackTest,DataProvider};

/**
 * @covers HackHttp\Client\Cookie\SetCookie
 */
class SetCookieTest extends HackTest
{
    public function testInitializesDefaultValues(): void
    {
        $cookie = new SetCookie();
        Helper::assertSame('/', $cookie->getPath());
    }

    public function testConvertsDateTimeMaxAgeToUnixTimestamp(): void
    {
        $cookie = new SetCookie(dict['Expires' => 'November 20, 1984']);
        expect($cookie->getExpires() is int)->toBeTrue();
    }

    public function testAddsExpiresBasedOnMaxAge(): void
    {
        $t = \time();
        $cookie = new SetCookie(dict['Max-Age' => 100]);
        Helper::assertEquals($t + 100, $cookie->getExpires());
    }

    public function testHoldsValues(): void
    {
        $t = \time();
        $data = dict[
            'Name'     => 'foo',
            'Value'    => 'baz',
            'Path'     => '/bar',
            'Domain'   => 'baz.com',
            'Expires'  => $t,
            'Max-Age'  => 100,
            'Secure'   => true,
            'Discard'  => true,
            'HttpOnly' => true,
            'foo'      => 'baz',
            'bar'      => 'bam'
        ];

        $cookie = new SetCookie($data);
        Helper::assertEquals($data, $cookie->toArray());

        Helper::assertSame('foo', $cookie->getName());
        Helper::assertSame('baz', $cookie->getValue());
        Helper::assertSame('baz.com', $cookie->getDomain());
        Helper::assertSame('/bar', $cookie->getPath());
        Helper::assertSame($t, $cookie->getExpires());
        Helper::assertSame(100, $cookie->getMaxAge());
        Helper::assertSame('baz', $cookie->toArray()['foo']);
        Helper::assertSame('bam', $cookie->toArray()['bar']);

        $cookie->setName('a');
        $cookie->setValue('b');
        $cookie->setPath('c');
        $cookie->setDomain('bar.com');
        $cookie->setExpires(10);
        $cookie->setMaxAge(200);
        $cookie->setSecure(false);
        $cookie->setHttpOnly(false);
        $cookie->setDiscard(false);

        Helper::assertSame('a', $cookie->getName());
        Helper::assertSame('b', $cookie->getValue());
        Helper::assertSame('c', $cookie->getPath());
        Helper::assertSame('bar.com', $cookie->getDomain());
        Helper::assertSame(10, $cookie->getExpires());
        Helper::assertSame(200, $cookie->getMaxAge());
    }

    public function testDeterminesIfExpired(): void
    {
        $c = new SetCookie();
        $c->setExpires(10);
        Helper::assertTrue($c->isExpired());
        $c->setExpires(\time() + 10000);
        Helper::assertFalse($c->isExpired());
    }

    public function testMatchesDomain(): void
    {
        $cookie = new SetCookie();
        Helper::assertTrue($cookie->matchesDomain('baz.com'));

        $cookie->setDomain('baz.com');
        Helper::assertTrue($cookie->matchesDomain('baz.com'));
        Helper::assertFalse($cookie->matchesDomain('bar.com'));

        $cookie->setDomain('.baz.com');
        Helper::assertTrue($cookie->matchesDomain('.baz.com'));
        Helper::assertTrue($cookie->matchesDomain('foo.baz.com'));
        Helper::assertFalse($cookie->matchesDomain('baz.bar.com'));
        Helper::assertTrue($cookie->matchesDomain('baz.com'));

        $cookie->setDomain('.127.0.0.1');
        Helper::assertTrue($cookie->matchesDomain('127.0.0.1'));

        $cookie->setDomain('127.0.0.1');
        Helper::assertTrue($cookie->matchesDomain('127.0.0.1'));

        $cookie->setDomain('.com.');
        Helper::assertFalse($cookie->matchesDomain('baz.com'));

        $cookie->setDomain('.local');
        Helper::assertTrue($cookie->matchesDomain('example.local'));

        $cookie->setDomain('example.com/'); // malformed domain
        Helper::assertFalse($cookie->matchesDomain('example.com'));
    }

    public function pathMatchProvider(): vec<(string, string, bool)>
    {
        return vec[
            tuple('/foo', '/foo', true),
            tuple('/foo', '/Foo', false),
            tuple('/foo', '/fo', false),
            tuple('/foo', '/foo/bar', true),
            tuple('/foo', '/foo/bar/baz', true),
            tuple('/foo', '/foo/bar//baz', true),
            tuple('/foo', '/foobar', false),
            tuple('/foo/bar', '/foo', false),
            tuple('/foo/bar', '/foobar', false),
            tuple('/foo/bar', '/foo/bar', true),
            tuple('/foo/bar', '/foo/bar/', true),
            tuple('/foo/bar', '/foo/bar/baz', true),
            tuple('/foo/bar/', '/foo/bar', false),
            tuple('/foo/bar/', '/foo/bar/', true),
            tuple('/foo/bar/', '/foo/bar/baz', true),
        ];
    }

    <<DataProvider('pathMatchProvider')>>
    public function testMatchesPath(string $cookiePath, string $requestPath, bool $isMatch): void
    {
        $cookie = new SetCookie();
        $cookie->setPath($cookiePath);
        Helper::assertSame($isMatch, $cookie->matchesPath($requestPath));
    }

    public function cookieValidateProvider(): vec<(mixed, mixed, mixed, mixed)>
    {
        return vec[
            tuple('foo', 'baz', 'bar', true),
            tuple('0', '0', '0', true),
            tuple('foo[bar)', 'baz', 'bar', 'Cookie name must not contain invalid characters: ASCII Control characters (0-31;127), space, tab and the following characters: ()<>@,;:\"/?={}'),
            tuple('foo', '', 'bar', true),
            tuple('', 'baz', 'bar', 'The cookie name must not be empty'),
            tuple('foo', null, 'bar', 'The cookie value must not be empty'),
            tuple('foo', 'baz', '', 'The cookie domain must not be empty'),
            tuple("foo\r", 'baz', '0', 'Cookie name must not contain invalid characters: ASCII Control characters (0-31;127), space, tab and the following characters: ()<>@,;:\"/?={}'),
        ];
    }

    <<DataProvider('cookieValidateProvider')>>
    public function testValidatesCookies(mixed $name, mixed $value, mixed $domain, mixed $result): void
    {
        $cookie = new SetCookie(dict[
            'Name'   => $name,
            'Value'  => $value,
            'Domain' => $domain,
        ]);
        Helper::assertSame($result, $cookie->validate());
    }

    public function testDoesNotMatchIp(): void
    {
        $cookie = new SetCookie(dict['Domain' => '192.168.16.']);
        Helper::assertFalse($cookie->matchesDomain('192.168.16.121'));
    }

    public function testConvertsToString(): void
    {
        $t = 1382916008;
        $cookie = new SetCookie(dict[
            'Name' => 'test',
            'Value' => '123',
            'Domain' => 'foo.com',
            'Expires' => $t,
            'Path' => '/abc',
            'HttpOnly' => true,
            'Secure' => true
        ]);
        Helper::assertSame(
            'test=123; Domain=foo.com; Path=/abc; Expires=Sun, 27 Oct 2013 23:20:08 GMT; Secure; HttpOnly',
            $cookie->__toString()
        );
    }

    /**
     * Provides the parsed information from a cookie
     *
     * @return vec<(string, dict<arraykey, mixed>)>
     */
    public function cookieParserDataProvider(): vec<(string, dict<arraykey, mixed>)>
    {
        return vec[
            tuple(
                'ASIHTTPRequestTestCookie=This+is+the+value; expires=Sat, 26-Jul-2008 17:00:42 GMT; path=/tests; domain=allseeing-i.com; PHPSESSID=6c951590e7a9359bcedde25cda73e43c; path=/;',
                dict[
                    'Domain' => 'allseeing-i.com',
                    'Path' => '/',
                    'PHPSESSID' => '6c951590e7a9359bcedde25cda73e43c',
                    'Max-Age' => null,
                    'Expires' => 'Sat, 26-Jul-2008 17:00:42 GMT',
                    'Secure' => false,
                    'Discard' => false,
                    'Name' => 'ASIHTTPRequestTestCookie',
                    'Value' => 'This+is+the+value',
                    'HttpOnly' => false
                ]
            ),
            tuple('', dict[]),
            tuple('foo', dict[]),
            tuple('; foo', dict[]),
            tuple(
                'foo="bar"',
                dict[
                    'Name' => 'foo',
                    'Value' => '"bar"',
                    'Discard' => false,
                    'Domain' => null,
                    'Expires' => null,
                    'Max-Age' => null,
                    'Path' => '/',
                    'Secure' => false,
                    'HttpOnly' => false
                ]
            ),
            
            // Some of the following tests are based on https://github.com/zendframework/zf1/blob/master/tests/Zend/Http/CookieTest.php
            tuple(
                'justacookie=foo; domain=example.com',
                dict[
                    'Name' => 'justacookie',
                    'Value' => 'foo',
                    'Domain' => 'example.com',
                    'Discard' => false,
                    'Expires' => null,
                    'Max-Age' => null,
                    'Path' => '/',
                    'Secure' => false,
                    'HttpOnly' => false
                ]
            )
        ];
    }

    <<DataProvider('cookieParserDataProvider')>>
    public function testParseCookie(string $cookie, dict<arraykey, mixed> $parsed): void
    {

        $cookie = vec[$cookie];

        foreach ( $cookie as $v) {
            $c = SetCookie::fromString($v);
            $p = $c->toArray();

            if (isset($p['Expires'])) {
                // Remove expires values from the assertion if they are relatively equal
                if (\abs($p['Expires'] != \strtotime($parsed['Expires'] as string)) < 40) {
                    unset($p['Expires']);
                    unset($parsed['Expires']);
                }
            }

            if ($parsed) {
                foreach ($parsed as $key => $value) {
                    Helper::assertEquals($parsed[$key], $p[$key], 'Comparing ' . $key . ' ' . \var_export($value, true) . ' : ' . \var_export($parsed, true) . ' | ' . \var_export($p, true));
                }
                foreach ($p as $key => $value) {
                    Helper::assertEquals($p[$key], $parsed[$key], 'Comparing ' . $key . ' ' . \var_export($value, true) . ' : ' . \var_export($parsed, true) . ' | ' . \var_export($p, true));
                }
            } else {
                Helper::assertSame(dict[
                    'Name' => null,
                    'Value' => null,
                    'Domain' => null,
                    'Path' => '/',
                    'Max-Age' => null,
                    'Expires' => null,
                    'Secure' => false,
                    'Discard' => false,
                    'HttpOnly' => false,
                ], $p);
            }
        }
    }

    /**
     * Provides the data for testing isExpired
     *
     * @return array
     */
    public function isExpiredProvider(): vec<(string, bool)>
    {
        return vec[
            tuple(
                'FOO=bar; expires=Thu, 01 Jan 1970 00:00:00 GMT;',
                true,
            ),
            tuple(
                'FOO=bar; expires=Thu, 01 Jan 1970 00:00:01 GMT;',
                true,
            ),
            tuple(
                'FOO=bar; expires=' . \date(\DateTime::RFC1123, \time() + 10) . ';',
                false,
            ),
            tuple(
                'FOO=bar; expires=' . \date(\DateTime::RFC1123, \time() - 10) . ';',
                true,
            ),
            tuple(
                'FOO=bar;',
                false,
            ),
        ];
    }

    <<DataProvider('isExpiredProvider')>>
    public function testIsExpired(string $cookie, bool $expired): void
    {
        Helper::assertSame(
            $expired,
            SetCookie::fromString($cookie)->isExpired()
        );
    }
}
