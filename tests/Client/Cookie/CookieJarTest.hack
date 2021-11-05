
namespace HackHttp\Tests\Client\CookieJar;

use HackHttp\Tests\Helper;

use HackHttp\Client\Cookie\CookieJar;
use HackHttp\Client\Cookie\SetCookie;
use HackHttp\Message\Request;
use HackHttp\Message\Response;
use function Facebook\FBExpect\expect;
use type Facebook\HackTest\{HackTest,DataProvider};

/**
 * @covers \GuzzleHttp\Cookie\CookieJar
 */
class CookieJarTest extends HackTest
{

    protected function getTestCookies(): vec<SetCookie>
    {
        return vec[
            new SetCookie(dict['Name' => 'foo',  'Value' => 'bar', 'Domain' => 'foo.com', 'Path' => '/',    'Discard' => true]),
            new SetCookie(dict['Name' => 'test', 'Value' => '123', 'Domain' => 'baz.com', 'Path' => '/foo', 'Expires' => 2]),
            new SetCookie(dict['Name' => 'you',  'Value' => '123', 'Domain' => 'bar.com', 'Path' => '/boo', 'Expires' => \time() + 1000])
        ];
    }

    public function testCreatesFromArray(): void
    {
        $jar = CookieJar::fromArray(dict[
            'foo' => 'bar',
            'baz' => 'bam'
        ], 'example.com');
        expect($jar->count())->toBeSame(2);
    }

    public function testEmptyJarIsCountable(): void
    {
        $jar = new CookieJar();
        expect($jar->count())->toBeSame(0);
    }

    public function testGetsCookiesByName(): void
    {
        $jar = new CookieJar();
        $cookies = $this->getTestCookies();
        foreach ($this->getTestCookies() as $cookie) {
            $jar->setCookie($cookie);
        }

        $testCookie = $cookies[0];
        Helper::assertEquals($testCookie, $jar->getCookieByName($testCookie->getName()));
        Helper::assertNull($jar->getCookieByName("doesnotexist"));
        Helper::assertNull($jar->getCookieByName(""));
    }

    /**
     * Provides test data for cookie cookieJar retrieval
     */
    public function getCookiesDataProvider(): vec<(vec<string>, string, string, string, bool)>
    {
        return vec[
            tuple(vec['foo', 'baz', 'test', 'muppet', 'googoo'], '', '', '', false),
            tuple(vec['foo', 'baz', 'muppet', 'googoo'], '', '', '', true),
            tuple(vec['googoo'], 'www.example.com', '', '', false),
            tuple(vec['muppet', 'googoo'], 'test.y.example.com', '', '', false),
            tuple(vec['foo', 'baz'], 'example.com', '', '', false),
            tuple(vec['muppet'], 'x.y.example.com', '/acme/', '', false),
            tuple(vec['muppet'], 'x.y.example.com', '/acme/test/', '', false),
            tuple(vec['googoo'], 'x.y.example.com', '/test/acme/test/', '', false),
            tuple(vec['foo', 'baz'], 'example.com', '', '', false),
            tuple(vec['baz'], 'example.com', '', 'baz', false),
        ];
    }

    public function testStoresAndRetrievesCookies(): void
    {
        $jar = new CookieJar();
        $cookies = $this->getTestCookies();
        foreach ($cookies as $cookie) {
            Helper::assertTrue($jar->setCookie($cookie));
        }

        Helper::assertCount(3, $jar->toArray());
    }

    public function testRemovesTemporaryCookies(): void
    {
        $jar = new CookieJar();

        $cookies = $this->getTestCookies();
        foreach ($this->getTestCookies() as $cookie) {
            $jar->setCookie($cookie);
        }
        $jar->clearSessionCookies();
        Helper::assertEquals(
            vec[$cookies[1], $cookies[2]],
            vec($jar->getIterator())
        );
    }

    public function testRemovesSelectively(): void
    {
        $jar = new CookieJar();

        foreach ($this->getTestCookies() as $cookie) {
            $jar->setCookie($cookie);
        }

        // Remove foo.com cookies
        $jar->clear('foo.com');
        Helper::assertCount(2, $jar->toArray());
        // Try again, removing no further cookies
        $jar->clear('foo.com');
        Helper::assertCount(2, $jar->toArray());

        // Remove bar.com cookies with path of /boo
        $jar->clear('bar.com', '/boo');
        Helper::assertCount(1, $jar->toArray());

        // Remove cookie by name
        $jar->clear(null, null, 'test');
        Helper::assertCount(0, $jar->toArray());
    }

    public function testDoesNotAddIncompleteCookies(): void
    {
        $jar = new CookieJar();

        Helper::assertFalse($jar->setCookie(new SetCookie()));
        Helper::assertFalse($jar->setCookie(new SetCookie(dict[
            'Name' => 'foo'
        ])));
        Helper::assertFalse($jar->setCookie(new SetCookie(dict[
            'Name' => false
        ])));
        Helper::assertFalse($jar->setCookie(new SetCookie(dict[
            'Name' => true
        ])));
        Helper::assertFalse($jar->setCookie(new SetCookie(dict[
            'Name'   => 'foo',
            'Domain' => 'foo.com'
        ])));
    }

    public function testDoesNotAddEmptyCookies(): void
    {
        $jar = new CookieJar();
        Helper::assertFalse($jar->setCookie(new SetCookie(dict[
            'Name'   => '',
            'Domain' => 'foo.com',
            'Value'  => 0
        ])));
    }

    public function testDoesAddValidCookies(): void
    {
        $jar = new CookieJar();
        Helper::assertTrue($jar->setCookie(new SetCookie(dict[
            'Name'   => '0',
            'Domain' => 'foo.com',
            'Value'  => 0
        ])));
        
        Helper::assertTrue($jar->setCookie(new SetCookie(dict[
            'Name'   => 'foo',
            'Domain' => 'foo.com',
            'Value'  => 0
        ])));
        
        Helper::assertTrue($jar->setCookie(new SetCookie(dict[
            'Name'   => 'foo',
            'Domain' => 'foo.com',
            'Value'  => 0.0
        ])));
        
        Helper::assertTrue($jar->setCookie(new SetCookie(dict[
            'Name'   => 'foo',
            'Domain' => 'foo.com',
            'Value'  => '0'
        ])));
        
    }

    public function testOverwritesCookiesThatAreOlderOrDiscardable(): void
    {
        $t = \time() + 1000;
        $data = dict[
            'Name'    => 'foo',
            'Value'   => 'bar',
            'Domain'  => '.example.com',
            'Path'    => '/',
            'Max-Age' => 86400,
            'Secure'  => true,
            'Discard' => true,
            'Expires' => $t
        ];

        $jar = new CookieJar();
        // Make sure that the discard cookie is overridden with the non-discard
        Helper::assertTrue($jar->setCookie(new SetCookie($data)));
        Helper::assertCount(1, $jar->toArray());

        $data['Discard'] = false;
        Helper::assertTrue($jar->setCookie(new SetCookie($data)));
        Helper::assertCount(1, $jar->toArray());

    
        // Make sure it doesn't duplicate the cookie
        $jar->setCookie(new SetCookie($data));
        Helper::assertCount(1, $jar->toArray());

        // Make sure the more future-ful expiration date supersede the other
        $data['Expires'] = \time() + 2000;
        Helper::assertTrue($jar->setCookie(new SetCookie($data)));
        Helper::assertCount(1, $jar->toArray());
    }

    public function testOverwritesCookiesThatHaveChanged(): void
    {
        $t = \time() + 1000;
        $data = dict[
            'Name'    => 'foo',
            'Value'   => 'bar',
            'Domain'  => '.example.com',
            'Path'    => '/',
            'Max-Age' => 86400,
            'Secure'  => true,
            'Discard' => true,
            'Expires' => $t
        ];

        $jar = new CookieJar();
        // Make sure that the discard cookie is overridden with the non-discard
        Helper::assertTrue($jar->setCookie(new SetCookie($data)));

        $data['Value'] = 'boo';
        Helper::assertTrue($jar->setCookie(new SetCookie($data)));
        Helper::assertCount(1, $jar->toArray());

        // Changing the value plus a parameter also must overwrite the existing one
        $data['Value'] = 'zoo';
        $data['Secure'] = false;
        Helper::assertTrue($jar->setCookie(new SetCookie($data)));
        Helper::assertCount(1, $jar->toArray());

    }

    public function testAddsCookiesFromResponseWithRequest(): void
    {
        $jar = new CookieJar();
        $response = new Response(200, dict[
            'Set-Cookie' => vec["fpc=d=.Hm.yh4.1XmJWjJfs4orLQzKzPImxklQoxXSHOZATHUSEFciRueW_7704iYUtsXNEXq0M92Px2glMdWypmJ7HIQl6XIUvrZimWjQ3vIdeuRbI.FNQMAfcxu_XN1zSx7l.AcPdKL6guHc2V7hIQFhnjRW0rxm2oHY1P4bGQxFNz7f.tHm12ZD3DbdMDiDy7TBXsuP4DM-&v=2; expires=Fri, 02-Mar-2019 02:17:40 GMT;"]
        ]);
        $request = new Request('GET', 'http://www.example.com');
        $jar->extractCookies($request, $response);
        Helper::assertCount(1, $jar->toArray());
    }

    public function getMatchingCookiesDataProvider(): vec<(string, string)>
    {
        return vec[
            tuple('https://example.com', 'foo=bar; baz=foobar'),
            tuple('http://example.com', ''),
            tuple('https://example.com:8912', 'foo=bar; baz=foobar'),
            tuple('https://foo.example.com', 'foo=bar; baz=foobar'),
            tuple('http://foo.example.com/test/acme/', 'googoo=gaga')
        ];
    }

    <<DataProvider('getMatchingCookiesDataProvider')>>
    public function testReturnsCookiesMatchingRequests(string $url, string $cookies): void
    {
        $bag = vec[
            new SetCookie(dict[
                'Name'    => 'foo',
                'Value'   => 'bar',
                'Domain'  => 'example.com',
                'Path'    => '/',
                'Max-Age' => '86400',
                'Secure'  => true
            ]),
            new SetCookie(dict[
                'Name'    => 'baz',
                'Value'   => 'foobar',
                'Domain'  => 'example.com',
                'Path'    => '/',
                'Max-Age' => '86400',
                'Secure'  => true
            ]),
            new SetCookie(dict[
                'Name'    => 'test',
                'Value'   => '123',
                'Domain'  => 'www.foobar.com',
                'Path'    => '/path/',
                'Discard' => true
            ]),
            new SetCookie(dict[
                'Name'    => 'muppet',
                'Value'   => 'cookie_monster',
                'Domain'  => '.y.example.com',
                'Path'    => '/acme/',
                'Expires' => \time() + 86400
            ]),
            new SetCookie(dict[
                'Name'    => 'googoo',
                'Value'   => 'gaga',
                'Domain'  => '.example.com',
                'Path'    => '/test/acme/',
                'Max-Age' => 1500
            ])
        ];

        $jar = new CookieJar();
        foreach ($bag as $cookie) {
            $jar->setCookie($cookie);
        }

        $request = new Request('GET', $url);
        $request = $jar->withCookieHeader($request);
        Helper::assertSame($cookies, $request->getHeaderLine('Cookie'));
    }


    public function testDeletesCookiesByName(): void
    {
        $cookies = $this->getTestCookies();
        $cookies[] = new SetCookie(dict[
            'Name' => 'other',
            'Value' => '123',
            'Domain' => 'bar.com',
            'Path' => '/boo',
            'Expires' => \time() + 1000
        ]);
        $jar = new CookieJar();
        foreach ($cookies as $cookie) {
            $jar->setCookie($cookie);
        }
        Helper::assertCount(4, $jar->toArray());
        $jar->clear('bar.com', '/boo', 'other');
        Helper::assertCount(3, $jar->toArray());
        $names = \array_map((SetCookie $c): string ==> {
            return $c->getName();
        }, vec($jar->getIterator()));
        Helper::assertSame(vec['foo', 'test', 'you'], vec($names));
    }

    public function testCanConvertToAndLoadFromArray(): void
    {
        $jar = new CookieJar(true);
        foreach ($this->getTestCookies() as $cookie) {
            $jar->setCookie($cookie);
        }
        Helper::assertCount(3, $jar->toArray());
        $arr = $jar->toArray();
        Helper::assertCount(3, $arr);
        $newCookieJar = new CookieJar(false, $arr);
        Helper::assertCount(3, $newCookieJar->toArray());
        Helper::assertSame($jar->toArray(), $newCookieJar->toArray());
    }

}
