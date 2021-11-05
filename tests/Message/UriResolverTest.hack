namespace HackHttp\Tests\Message;

use HackHttp\Tests\Helper;

use HackHttp\Message\Uri;
use HackHttp\Message\UriResolver;
use function Facebook\FBExpect\expect;
use type Facebook\HackTest\{HackTest, DataProvider};
use HackHttp\Message\UriInterface;

/**
 * @covers HackHttp\Message\UriResolver
 */
class UriResolverTest extends HackTest
{
    const RFC3986_BASE = 'http://a/b/c/d;p?q';

    <<DataProvider('getResolveTestCases')>>
    public function testResolveUri(string $base, string $rel, string $expectedTarget): void
    {
        $baseUri = new Uri($base);
        $targetUri = UriResolver::resolve($baseUri, new Uri($rel));

        Helper::assertSame($expectedTarget, $targetUri->__toString());
        // This ensures there are no test cases that only work in the resolve() direction but not the
        // opposite via relativize(). This can happen when both base and rel URI are relative-path
        // references resulting in another relative-path URI.
        Helper::assertSame($expectedTarget, UriResolver::resolve($baseUri, $targetUri)->__toString());
    }

    <<DataProvider('getResolveTestCases')>>
    public function testRelativizeUri(string $base, string $expectedRelativeReference, string $target): void
    {
        $baseUri = new Uri($base);
        $relativeUri = UriResolver::relativize($baseUri, new Uri($target));

        Helper::assertInstanceOf(UriInterface::class, $relativeUri);
        // There are test-cases with too many dot-segments and relative references that are equal like "." == "./".
        // So apart from the same-as condition, this alternative success condition is necessary.
        Helper::assertTrue(
            $expectedRelativeReference === $relativeUri->__toString()
            || $target ===  UriResolver::resolve($baseUri, $relativeUri)->__toString(),
            \sprintf(
                '"base %s, expectedRelativeReference %s, target %s, relative %s" does not resolve to the target from the base ',
                $base,  $expectedRelativeReference, $target, $relativeUri->__toString()
            )
        );
    }

    <<DataProvider('getRelativizeTestCases')>>
    public function testRelativizeUriWithUniqueTests(string $base, string $target, string $expectedRelativeReference): void
    {
        $baseUri = new Uri($base);
        $targetUri = new Uri($target);
        $relativeUri = UriResolver::relativize($baseUri, $targetUri);

        Helper::assertInstanceOf(UriInterface::class, $relativeUri);
        Helper::assertSame($expectedRelativeReference, $relativeUri->__toString());

        Helper::assertSame( UriResolver::resolve($baseUri, $targetUri)->__toString(), 
            UriResolver::resolve($baseUri, $relativeUri)->__toString());
    }

    public function getResolveTestCases(): vec<(string, string, string)>
    {
        return vec[
            tuple(self::RFC3986_BASE, 'g:h',           'g:h'),
            tuple(self::RFC3986_BASE, 'g',             'http://a/b/c/g'),
            tuple(self::RFC3986_BASE, './g',           'http://a/b/c/g'),
            tuple(self::RFC3986_BASE, 'g/',            'http://a/b/c/g/'),
            tuple(self::RFC3986_BASE, '/g',            'http://a/g'),
            tuple(self::RFC3986_BASE, '//g',           'http://g'),
            tuple(self::RFC3986_BASE, '?y',            'http://a/b/c/d;p?y'),
            tuple(self::RFC3986_BASE, 'g?y',           'http://a/b/c/g?y'),
            tuple(self::RFC3986_BASE, '#s',            'http://a/b/c/d;p?q#s'),
            tuple(self::RFC3986_BASE, 'g#s',           'http://a/b/c/g#s'),
            tuple(self::RFC3986_BASE, 'g?y#s',         'http://a/b/c/g?y#s'),
            tuple(self::RFC3986_BASE, ';x',            'http://a/b/c/;x'),
            tuple(self::RFC3986_BASE, 'g;x',           'http://a/b/c/g;x'),
            tuple(self::RFC3986_BASE, 'g;x?y#s',       'http://a/b/c/g;x?y#s'),
            tuple(self::RFC3986_BASE, '',              self::RFC3986_BASE),
            tuple(self::RFC3986_BASE, '.',             'http://a/b/c/'),
            tuple(self::RFC3986_BASE, './',            'http://a/b/c/'),
            tuple(self::RFC3986_BASE, '..',            'http://a/b/'),
            tuple(self::RFC3986_BASE, '../',           'http://a/b/'),
            tuple(self::RFC3986_BASE, '../g',          'http://a/b/g'),
            tuple(self::RFC3986_BASE, '../..',         'http://a/'),
            tuple(self::RFC3986_BASE, '../../',        'http://a/'),
            tuple(self::RFC3986_BASE, '../../g',       'http://a/g'),
            tuple(self::RFC3986_BASE, '../../../g',    'http://a/g'),
            tuple(self::RFC3986_BASE, '../../../../g', 'http://a/g'),
            tuple(self::RFC3986_BASE, '/./g',          'http://a/g'),
            tuple(self::RFC3986_BASE, '/../g',         'http://a/g'),
            tuple(self::RFC3986_BASE, 'g.',            'http://a/b/c/g.'),
            tuple(self::RFC3986_BASE, '.g',            'http://a/b/c/.g'),
            tuple(self::RFC3986_BASE, 'g..',           'http://a/b/c/g..'),
            tuple(self::RFC3986_BASE, '..g',           'http://a/b/c/..g'),
            tuple(self::RFC3986_BASE, './../g',        'http://a/b/g'),
            tuple(self::RFC3986_BASE, 'foo////g',      'http://a/b/c/foo////g'),
            tuple(self::RFC3986_BASE, './g/.',         'http://a/b/c/g/'),
            tuple(self::RFC3986_BASE, 'g/./h',         'http://a/b/c/g/h'),
            tuple(self::RFC3986_BASE, 'g/../h',        'http://a/b/c/h'),
            tuple(self::RFC3986_BASE, 'g;x=1/./y',     'http://a/b/c/g;x=1/y'),
            tuple(self::RFC3986_BASE, 'g;x=1/../y',    'http://a/b/c/y'),
            // dot-segments in the query or fragment
            tuple(self::RFC3986_BASE, 'g?y/./x',       'http://a/b/c/g?y/./x'),
            tuple(self::RFC3986_BASE, 'g?y/../x',      'http://a/b/c/g?y/../x'),
            tuple(self::RFC3986_BASE, 'g#s/./x',       'http://a/b/c/g#s/./x'),
            tuple(self::RFC3986_BASE, 'g#s/../x',      'http://a/b/c/g#s/../x'),
            tuple(self::RFC3986_BASE, 'g#s/../x',      'http://a/b/c/g#s/../x'),
            tuple(self::RFC3986_BASE, '?y#s',          'http://a/b/c/d;p?y#s'),
            // base with fragment
            tuple('http://a/b/c?q#s', '?y',            'http://a/b/c?y'),
            // base with user info
            tuple('http://u@a/b/c/d;p?q', '.',         'http://u@a/b/c/'),
            tuple('http://u:p@a/b/c/d;p?q', '.',       'http://u:p@a/b/c/'),
            // path ending with slash or no slash at all
            tuple('http://a/b/c/d/',  'e',             'http://a/b/c/d/e'),
            tuple('urn:no-slash',     'e',             'urn:e'),
            // path ending without slash and multi-segment relative part
            tuple('http://a/b/c',     'd/e',           'http://a/b/d/e'),
            // falsey relative parts
            tuple(self::RFC3986_BASE, '//0',           'http://0'),
            tuple(self::RFC3986_BASE, '0',             'http://a/b/c/0'),
            tuple(self::RFC3986_BASE, '?0',            'http://a/b/c/d;p?0'),
            tuple(self::RFC3986_BASE, '#0',            'http://a/b/c/d;p?q#0'),
            // absolute path base URI
            tuple('/a/b/',            '',              '/a/b/'),
            tuple('/a/b',             '',              '/a/b'),
            tuple('/',                'a',             '/a'),
            tuple('/',                'a/b',           '/a/b'),
            tuple('/a/b',             'g',             '/a/g'),
            tuple('/a/b/c',           './',            '/a/b/'),
            tuple('/a/b/',            '../',           '/a/'),
            tuple('/a/b/c',           '../',           '/a/'),
            tuple('/a/b/',            '../../x/y/z/',  '/x/y/z/'),
            tuple('/a/b/c/d/e',       '../../../c/d',  '/a/c/d'),
            tuple('/a/b/c//',         '../',           '/a/b/c/'),
            tuple('/a/b/c/',          './/',           '/a/b/c//'),
            tuple('/a/b/c',           '../../../../a', '/a'),
            tuple('/a/b/c',           '../../../..',   '/'),
            // not actually a dot-segment
            tuple('/a/b/c',           '..a/b..',           '/a/b/..a/b..'),
            // '' cannot be used as relative reference as it would inherit the base query component
            tuple('/a/b?q',           'b',             '/a/b'),
            tuple('/a/b/?q',          './',            '/a/b/'),
            // path with colon: "with:colon" would be the wrong relative reference
            tuple('/a/',              './with:colon',  '/a/with:colon'),
            tuple('/a/',              'b/with:colon',  '/a/b/with:colon'),
            tuple('/a/',              './:b/',         '/a/:b/'),
            // relative path references
            tuple('a',               'a/b',            'a/b'),
            tuple('',                 '',              ''),
            tuple('',                 '..',            ''),
            tuple('/',                '..',            '/'),
            tuple('urn:a/b',          '..//a/b',       'urn:/a/b'),
            // network path references
            // empty base path and relative-path reference
            tuple('//example.com',    'a',             '//example.com/a'),
            // path starting with two slashes
            tuple('//example.com//two-slashes', './',  '//example.com//'),
            tuple('//example.com',    './/',           '//example.com//'),
            tuple('//example.com/',   './/',           '//example.com//'),
            // base URI has less components than relative URI
            tuple('/',                '//a/b?q#h',     '//a/b?q#h'),
            tuple('/',                'urn:/',         'urn:/'),
        ];
    }

    /**
     * Some additional tests to getResolveTestCases() that only make sense for relativize.
     */
    public function getRelativizeTestCases(): vec<(string, string, string)> 
    {
        return vec[
            // targets that are relative-path references are returned as-is
            tuple('a/b',             'b/c',          'b/c'),
            tuple('a/b/c',           '../b/c',       '../b/c'),
            tuple('a',               '',             ''),
            tuple('a',               './',           './'),
            tuple('a',               'a/..',         'a/..'),
            tuple('/a/b/?q',         '?q#h',         '?q#h'),
            tuple('/a/b/?q',         '#h',           '#h'),
            tuple('/a/b/?q',         'c#h',          'c#h'),
            // If the base URI has a query but the target has none, we cannot return an empty path reference as it would
            // inherit the base query component when resolving.
            tuple('/a/b/?q',         '/a/b/#h',      './#h'),
            tuple('/',               '/#h',          '#h'),
            tuple('/',               '/',            ''),
            tuple('http://a',        'http://a/',    './'),
            tuple('urn:a/b?q',       'urn:x/y?q',    '../x/y?q'),
            tuple('urn:',            'urn:/',        './/'),
            tuple('urn:a/b?q',       'urn:',         '../'),
            // target URI has less components than base URI
            tuple('http://a/b/',     '//a/b/c',      'c'),
            tuple('http://a/b/',     '/b/c',         'c'),
            tuple('http://a/b/',     '/x/y',         '../x/y'),
            tuple('http://a/b/',     '/',            '../'),
            // absolute target URI without authority but base URI has one
            tuple('urn://a/b/',      'urn:/b/',      'urn:/b/'),
        ];
    }
}
