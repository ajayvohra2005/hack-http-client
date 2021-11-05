namespace HackHttp\Tests\Message;

use HackHttp\Tests\Helper;

use HackHttp\Message\MalformedUriException;
use HackHttp\Message\Uri;
use function Facebook\FBExpect\expect; 
use type Facebook\HackTest\{HackTest, DataProvider};

/**
 * @covers HackHttp\Message\Uri
 */
class UriTest extends HackTest
{
    public function testParsesProvidedUri(): void
    {
        $uri = new Uri('https://user:pass@example.com:8080/path/123?q=abc#test');

        Helper::assertSame('https', $uri->getScheme());
        Helper::assertSame('user:pass@example.com:8080', $uri->getAuthority());
        Helper::assertSame('user:pass', $uri->getUserInfo());
        Helper::assertSame('example.com', $uri->getHost());
        Helper::assertSame(8080, $uri->getPort());
        Helper::assertSame('/path/123', $uri->getPath());
        Helper::assertSame('q=abc', $uri->getQuery());
        Helper::assertSame('test', $uri->getFragment());
        Helper::assertSame('https://user:pass@example.com:8080/path/123?q=abc#test', $uri->__toString());
    }

    public function testCanTransformAndRetrievePartsIndividually(): void
    {
        $uri = (new Uri())
            ->withScheme('https')
            ->withUserInfo('user', 'pass')
            ->withHost('example.com')
            ->withPort(8080)
            ->withPath('/path/123')
            ->withQuery('q=abc')
            ->withFragment('test');

        Helper::assertSame('https', $uri->getScheme());
        Helper::assertSame('user:pass@example.com:8080', $uri->getAuthority());
        Helper::assertSame('user:pass', $uri->getUserInfo());
        Helper::assertSame('example.com', $uri->getHost());
        Helper::assertSame(8080, $uri->getPort());
        Helper::assertSame('/path/123', $uri->getPath());
        Helper::assertSame('q=abc', $uri->getQuery());
        Helper::assertSame('test', $uri->getFragment());
        Helper::assertSame('https://user:pass@example.com:8080/path/123?q=abc#test', $uri->__toString());
    }

    <<DataProvider('getValidUris')>>
    public function testValidUrisStayValid(string $input): void
    {
        $uri = new Uri($input);

        Helper::assertSame($input, $uri->__toString());
    }

    <<DataProvider('getValidUris')>>
    public function testFromParts(string $input): void
    {
        $uri = Uri::fromParts(\parse_url($input));

        Helper::assertSame($input, $uri->__toString());
    }

    public function getValidUris(): vec< (string) >
    {
        return vec[
            tuple('urn:path-rootless'),
            tuple('urn:path:with:colon'),
            tuple('urn:/path-absolute'),
            tuple('urn:/'),
            // only scheme with empty path
            tuple('urn:'),
            // only path
            tuple('/'),
            tuple('relative/'),
            tuple('0'),
            // same document reference
            tuple(''),
            // network path without scheme
            tuple('//example.org'),
            tuple('//example.org/'),
            tuple('//example.org?q#h'),
            // only query
            tuple('?q'),
            tuple('?q=abc&foo=bar'),
            // only fragment
            tuple('#fragment'),
            // dot segments are not removed automatically
            tuple('./foo/../bar'),
        ];
    }

    <<DataProvider('getInvalidUris')>>
    public function testInvalidUrisThrowException(string $invalidUri): void
    {
        expect(() ==> new Uri($invalidUri))->toThrow(MalformedUriException::class);
    }

    public function getInvalidUris(): vec< (string) >
    {
        return vec[
            // parse_url() requires the host component which makes sense for http(s)
            // but not when the scheme is not known or different. So '//' or '///' is
            // currently invalid as well but should not according to RFC 3986.
            tuple('http://'),
            tuple('urn://host:with:colon') // host cannot contain ":"
        ];
    }

    public function testPortMustBeValid(): void
    {
        expect(() ==> (new Uri())->withPort(100000))->toThrow(\InvalidArgumentException::class, 'Invalid port: 100000. Must be between 0 and 65535');
    }

    public function testWithPortCannotBeNegative(): void
    {
        expect(() ==> (new Uri())->withPort(-1))->toThrow(\InvalidArgumentException::class, 'Invalid port: -1. Must be between 0 and 65535');
    }

    public function testParseUriPortCannotBeNegative(): void
    {
        expect(() ==> new Uri('//example.com:-1'))->toThrow(\InvalidArgumentException::class, 'Unable to parse URI');
    }

    public function testCanParseFalseyUriParts(): void
    {
        $uri = new Uri('0://0:0@0/0?0#0');

        Helper::assertSame('0', $uri->getScheme());
        Helper::assertSame('0:0@0', $uri->getAuthority());
        Helper::assertSame('0:0', $uri->getUserInfo());
        Helper::assertSame('0', $uri->getHost());
        Helper::assertSame('/0', $uri->getPath());
        Helper::assertSame('0', $uri->getQuery());
        Helper::assertSame('0', $uri->getFragment());
        Helper::assertSame('0://0:0@0/0?0#0', $uri->__toString());
    }

    public function testCanConstructFalseyUriParts(): void
    {
        $uri = (new Uri())
            ->withScheme('0')
            ->withUserInfo('0', '0')
            ->withHost('0')
            ->withPath('/0')
            ->withQuery('0')
            ->withFragment('0');

        Helper::assertSame('0', $uri->getScheme());
        Helper::assertSame('0:0@0', $uri->getAuthority());
        Helper::assertSame('0:0', $uri->getUserInfo());
        Helper::assertSame('0', $uri->getHost());
        Helper::assertSame('/0', $uri->getPath());
        Helper::assertSame('0', $uri->getQuery());
        Helper::assertSame('0', $uri->getFragment());
        Helper::assertSame('0://0:0@0/0?0#0', $uri->__toString());
    }

    <<DataProvider('getPortTestCases')>>
    public function testIsDefaultPort(string $scheme, ?int $port, bool $isDefaultPort): void
    {
        $uri = (new Uri())->withScheme($scheme)->withPort($port);
        expect($uri->getScheme())->toBeSame($scheme);
        Helper::assertSame($isDefaultPort, Uri::isDefaultPort($uri));
    }

    public function getPortTestCases(): vec<(string, ?int, bool)>
    {
        return vec[
            tuple('http', null, true),
            tuple('http', 80, true),
            tuple('http', 8080, false),
            tuple('https', null, true),
            tuple('https', 443, true),
            tuple('https', 444, false),
            tuple('ftp', 21, true),
            tuple('gopher', 70, true),
            tuple('nntp', 119, true),
            tuple('news', 119, true),
            tuple('telnet', 23, true),
            tuple('tn3270', 23, true),
            tuple('imap', 143, true),
            tuple('pop', 110, true),
            tuple('ldap', 389, true),
        ];
    }

    public function testIsAbsolute(): void
    {
        Helper::assertTrue(Uri::isAbsolute(new Uri('http://example.org')));
        Helper::assertFalse(Uri::isAbsolute(new Uri('//example.org')));
        Helper::assertFalse(Uri::isAbsolute(new Uri('/abs-path')));
        Helper::assertFalse(Uri::isAbsolute(new Uri('rel-path')));
    }

    public function testIsNetworkPathReference(): void
    {
        Helper::assertFalse(Uri::isNetworkPathReference(new Uri('http://example.org')));
        Helper::assertTrue(Uri::isNetworkPathReference(new Uri('//example.org')));
        Helper::assertFalse(Uri::isNetworkPathReference(new Uri('/abs-path')));
        Helper::assertFalse(Uri::isNetworkPathReference(new Uri('rel-path')));
    }

    public function testIsAbsolutePathReference(): void
    {
        Helper::assertFalse(Uri::isAbsolutePathReference(new Uri('http://example.org')));
        Helper::assertFalse(Uri::isAbsolutePathReference(new Uri('//example.org')));
        Helper::assertTrue(Uri::isAbsolutePathReference(new Uri('/abs-path')));
        Helper::assertTrue(Uri::isAbsolutePathReference(new Uri('/')));
        Helper::assertFalse(Uri::isAbsolutePathReference(new Uri('rel-path')));
    }

    public function testIsRelativePathReference(): void
    {
        Helper::assertFalse(Uri::isRelativePathReference(new Uri('http://example.org')));
        Helper::assertFalse(Uri::isRelativePathReference(new Uri('//example.org')));
        Helper::assertFalse(Uri::isRelativePathReference(new Uri('/abs-path')));
        Helper::assertTrue(Uri::isRelativePathReference(new Uri('rel-path')));
        Helper::assertTrue(Uri::isRelativePathReference(new Uri('')));
    }

    public function testIsSameDocumentReference(): void
    {
        Helper::assertFalse(Uri::isSameDocumentReference(new Uri('http://example.org')));
        Helper::assertFalse(Uri::isSameDocumentReference(new Uri('//example.org')));
        Helper::assertFalse(Uri::isSameDocumentReference(new Uri('/abs-path')));
        Helper::assertFalse(Uri::isSameDocumentReference(new Uri('rel-path')));
        Helper::assertFalse(Uri::isSameDocumentReference(new Uri('?query')));
        Helper::assertTrue(Uri::isSameDocumentReference(new Uri('')));
        Helper::assertTrue(Uri::isSameDocumentReference(new Uri('#fragment')));

        $baseUri = new Uri('http://example.org/path?foo=bar');

        Helper::assertTrue(Uri::isSameDocumentReference(new Uri('#fragment'), $baseUri));
        Helper::assertTrue(Uri::isSameDocumentReference(new Uri('?foo=bar#fragment'), $baseUri));
        Helper::assertTrue(Uri::isSameDocumentReference(new Uri('/path?foo=bar#fragment'), $baseUri));
        Helper::assertTrue(Uri::isSameDocumentReference(new Uri('path?foo=bar#fragment'), $baseUri));
        Helper::assertTrue(Uri::isSameDocumentReference(new Uri('//example.org/path?foo=bar#fragment'), $baseUri));
        Helper::assertTrue(Uri::isSameDocumentReference(new Uri('http://example.org/path?foo=bar#fragment'), $baseUri));

        Helper::assertFalse(Uri::isSameDocumentReference(new Uri('https://example.org/path?foo=bar'), $baseUri));
        Helper::assertFalse(Uri::isSameDocumentReference(new Uri('http://example.com/path?foo=bar'), $baseUri));
        Helper::assertFalse(Uri::isSameDocumentReference(new Uri('http://example.org/'), $baseUri));
        Helper::assertFalse(Uri::isSameDocumentReference(new Uri('http://example.org'), $baseUri));

        Helper::assertFalse(Uri::isSameDocumentReference(new Uri('urn:/path'), new Uri('urn://example.com/path')));
    }

    public function testAddAndRemoveQueryValues(): void
    {
        $uri = new Uri();
        $uri = Uri::withQueryValue($uri, 'a', 'b');
        $uri = Uri::withQueryValue($uri, 'c', 'd');
        $uri = Uri::withQueryValue($uri, 'e', null);
        Helper::assertSame('a=b&c=d&e', $uri->getQuery());

        $uri = Uri::withoutQueryValue($uri, 'c');
        Helper::assertSame('a=b&e', $uri->getQuery());
        $uri = Uri::withoutQueryValue($uri, 'e');
        Helper::assertSame('a=b', $uri->getQuery());
        $uri = Uri::withoutQueryValue($uri, 'a');
        Helper::assertSame('', $uri->getQuery());
    }

    public function testScalarQueryValues(): void
    {
        $uri = new Uri();
        $uri = Uri::withQueryValues($uri, dict[
            "2" => 2,
            "1" => true,
            'false' => false,
            'float' => 3.1
        ]);

        Helper::assertSame('2=2&1=1&false=&float=3.1', $uri->getQuery());
    }

    public function testWithQueryValues(): void
    {
        $uri = new Uri();
        $uri = Uri::withQueryValues($uri, dict[
            'key1' => 'value1',
            'key2' => 'value2'
        ]);

        Helper::assertSame('key1=value1&key2=value2', $uri->getQuery());
    }

    public function testWithQueryValuesReplacesSameKeys(): void
    {
        $uri = new Uri();

        $uri = Uri::withQueryValues($uri, dict[
            'key1' => 'value1',
            'key2' => 'value2'
        ]);

        $uri = Uri::withQueryValues($uri, dict[
            'key2' => 'newvalue'
        ]);

        Helper::assertSame('key1=value1&key2=newvalue', $uri->getQuery());
    }

    public function testWithQueryValueReplacesSameKeys(): void
    {
        $uri = new Uri();
        $uri = Uri::withQueryValue($uri, 'a', 'b');
        $uri = Uri::withQueryValue($uri, 'c', 'd');
        $uri = Uri::withQueryValue($uri, 'a', 'e');
        Helper::assertSame('c=d&a=e', $uri->getQuery());
    }

    public function testWithoutQueryValueRemovesAllSameKeys(): void
    {
        $uri = (new Uri())->withQuery('a=b&c=d&a=e');
        $uri = Uri::withoutQueryValue($uri, 'a');
        Helper::assertSame('c=d', $uri->getQuery());
    }

    public function testRemoveNonExistingQueryValue(): void
    {
        $uri = new Uri();
        $uri = Uri::withQueryValue($uri, 'a', 'b');
        $uri = Uri::withoutQueryValue($uri, 'c');
        Helper::assertSame('a=b', $uri->getQuery());
    }

    public function testWithQueryValueHandlesEncoding(): void
    {
        $uri = new Uri();
        $uri = Uri::withQueryValue($uri, 'E=mc^2', 'ein&stein');
        Helper::assertSame('E%3Dmc%5E2=ein%26stein', $uri->getQuery(), 'Decoded key/value get encoded');

        $uri = new Uri();
        $uri = Uri::withQueryValue($uri, 'E%3Dmc%5e2', 'ein%26stein');
        Helper::assertSame('E%3Dmc%5e2=ein%26stein', $uri->getQuery(), 'Encoded key/value do not get double-encoded');
    }

    public function testWithoutQueryValueHandlesEncoding(): void
    {
        // It also tests that the case of the percent-encoding does not matter,
        // i.e. both lowercase "%3d" and uppercase "%5E" can be removed.
        $uri = (new Uri())->withQuery('E%3dmc%5E2=einstein&foo=bar');
        $uri = Uri::withoutQueryValue($uri, 'E=mc^2');
        Helper::assertSame('foo=bar', $uri->getQuery(), 'Handles key in decoded form');

        $uri = (new Uri())->withQuery('E%3dmc%5E2=einstein&foo=bar');
        $uri = Uri::withoutQueryValue($uri, 'E%3Dmc%5e2');
        Helper::assertSame('foo=bar', $uri->getQuery(), 'Handles key in encoded form');
    }

    public function testSchemeIsNormalizedToLowercase(): void
    {
        $uri = new Uri('HTTP://example.com');

        Helper::assertSame('http', $uri->getScheme());
        Helper::assertSame('http://example.com', $uri->__toString());

        $uri = (new Uri('//example.com'))->withScheme('HTTP');

        Helper::assertSame('http', $uri->getScheme());
        Helper::assertSame('http://example.com', $uri->__toString());
    }

    public function testHostIsNormalizedToLowercase(): void
    {
        $uri = new Uri('//eXaMpLe.CoM');

        Helper::assertSame('example.com', $uri->getHost());
        Helper::assertSame('//example.com', $uri->__toString());

        $uri = (new Uri())->withHost('eXaMpLe.CoM');

        Helper::assertSame('example.com', $uri->getHost());
        Helper::assertSame('//example.com', $uri->__toString());
    }

    public function testPortIsNullIfStandardPortForScheme(): void
    {
        // HTTPS standard port
        $uri = new Uri('https://example.com:443');
        Helper::assertNull($uri->getPort());
        Helper::assertSame('example.com', $uri->getAuthority());

        $uri = (new Uri('https://example.com'))->withPort(443);
        Helper::assertNull($uri->getPort());
        Helper::assertSame('example.com', $uri->getAuthority());

        // HTTP standard port
        $uri = new Uri('http://example.com:80');
        Helper::assertNull($uri->getPort());
        Helper::assertSame('example.com', $uri->getAuthority());

        $uri = (new Uri('http://example.com'))->withPort(80);
        Helper::assertNull($uri->getPort());
        Helper::assertSame('example.com', $uri->getAuthority());
    }

    public function testPortIsReturnedIfSchemeUnknown(): void
    {
        $uri = (new Uri('//example.com'))->withPort(80);

        Helper::assertSame(80, $uri->getPort());
        Helper::assertSame('example.com:80', $uri->getAuthority());
    }

    public function testStandardPortIsNullIfSchemeChanges(): void
    {
        $uri = new Uri('http://example.com:443');
        Helper::assertSame('http', $uri->getScheme());
        Helper::assertSame(443, $uri->getPort());

        $uri = $uri->withScheme('https');
        Helper::assertNull($uri->getPort());
    }

    public function testPortPassedAsStringIsCastedToInt(): void
    {
        $uri = (new Uri('//example.com'))->withPort(8080);

        Helper::assertSame(8080, $uri->getPort(), 'Port is returned as integer');
        Helper::assertSame('example.com:8080', $uri->getAuthority());
    }

    public function testPortCanBeRemoved(): void
    {
        $uri = (new Uri('http://example.com:8080'))->withPort(null);

        Helper::assertNull($uri->getPort());
        Helper::assertSame('http://example.com', $uri->__toString());
    }

    /**
     * In RFC 8986 the host is optional and the authority can only
     * consist of the user info and port.
     */
    public function testAuthorityWithUserInfoOrPortButWithoutHost(): void
    {
        $uri = (new Uri())->withUserInfo('user', 'pass');

        Helper::assertSame('user:pass', $uri->getUserInfo());
        Helper::assertSame('user:pass@', $uri->getAuthority());

        $uri = $uri->withPort(8080);
        Helper::assertSame(8080, $uri->getPort());
        Helper::assertSame('user:pass@:8080', $uri->getAuthority());
        Helper::assertSame('//user:pass@:8080', $uri->__toString());

        $uri = $uri->withUserInfo('');
        Helper::assertSame(':8080', $uri->getAuthority());
    }

    public function testHostInHttpUriDefaultsToLocalhost(): void
    {
        $uri = (new Uri())->withScheme('http');

        Helper::assertSame('localhost', $uri->getHost());
        Helper::assertSame('localhost', $uri->getAuthority());
        Helper::assertSame('http://localhost', $uri->__toString());
    }

    public function testHostInHttpsUriDefaultsToLocalhost(): void
    {
        $uri = (new Uri())->withScheme('https');

        Helper::assertSame('localhost', $uri->getHost());
        Helper::assertSame('localhost', $uri->getAuthority());
        Helper::assertSame('https://localhost', $uri->__toString());
    }

    public function testFileSchemeWithEmptyHostReconstruction(): void
    {
        $uri = new Uri('file:///tmp/filename.ext');

        Helper::assertSame('', $uri->getHost());
        Helper::assertSame('', $uri->getAuthority());
        Helper::assertSame('file:///tmp/filename.ext', $uri->__toString());
    }

    public function uriComponentsEncodingProvider(): vec<(string, string, string, string, string)>
    {
        $unreserved = 'a-zA-Z0-9.-_~!$&\'()*+,;=:@';

        return vec[
            // Percent encode spaces
            tuple('/pa th?q=va lue#frag ment', '/pa%20th', 'q=va%20lue', 'frag%20ment', '/pa%20th?q=va%20lue#frag%20ment'),
            // Percent encode multibyte
            tuple('/€?€#€', '/%E2%82%AC', '%E2%82%AC', '%E2%82%AC', '/%E2%82%AC?%E2%82%AC#%E2%82%AC'),
            // Don't encode something that's already encoded
            tuple('/pa%20th?q=va%20lue#frag%20ment', '/pa%20th', 'q=va%20lue', 'frag%20ment', '/pa%20th?q=va%20lue#frag%20ment'),
            // Percent encode invalid percent encodings
            tuple('/pa%2-th?q=va%2-lue#frag%2-ment', '/pa%252-th', 'q=va%252-lue', 'frag%252-ment', '/pa%252-th?q=va%252-lue#frag%252-ment'),
            // Don't encode path segments
            tuple('/pa/th//two?q=va/lue#frag/ment', '/pa/th//two', 'q=va/lue', 'frag/ment', '/pa/th//two?q=va/lue#frag/ment'),
            // Don't encode unreserved chars or sub-delimiters
            tuple("/$unreserved?$unreserved#$unreserved", "/$unreserved", $unreserved, $unreserved, "/$unreserved?$unreserved#$unreserved"),
            // Encoded unreserved chars are not decoded
            tuple('/p%61th?q=v%61lue#fr%61gment', '/p%61th', 'q=v%61lue', 'fr%61gment', '/p%61th?q=v%61lue#fr%61gment'),
        ];
    }

    <<DataProvider('uriComponentsEncodingProvider')>>
    public function testUriComponentsGetEncodedProperly(string $input, string $path, string $query, string $fragment, string $output): void
    {
        $uri = new Uri($input);
        Helper::assertSame($path, $uri->getPath());
        Helper::assertSame($query, $uri->getQuery());
        Helper::assertSame($fragment, $uri->getFragment());
        Helper::assertSame($output, $uri->__toString());
    }

    public function testWithPathEncodesProperly(): void
    {
        $uri = (new Uri())->withPath('/baz?#€/b%61r');
        // Query and fragment delimiters and multibyte chars are encoded.
        Helper::assertSame('/baz%3F%23%E2%82%AC/b%61r', $uri->getPath());
        Helper::assertSame('/baz%3F%23%E2%82%AC/b%61r', $uri->__toString());
    }

    public function testWithQueryEncodesProperly(): void
    {
        $uri = (new Uri())->withQuery('?=#&€=/&b%61r');
        // A query starting with a "?" is valid and must not be magically removed. Otherwise it would be impossible to
        // construct such an URI. Also the "?" and "/" does not need to be encoded in the query.
        Helper::assertSame('?=%23&%E2%82%AC=/&b%61r', $uri->getQuery());
        Helper::assertSame('??=%23&%E2%82%AC=/&b%61r', $uri->__toString());
    }

    public function testWithFragmentEncodesProperly(): void
    {
        $uri = (new Uri())->withFragment('#€?/b%61r');
        // A fragment starting with a "#" is valid and must not be magically removed. Otherwise it would be impossible to
        // construct such an URI. Also the "?" and "/" does not need to be encoded in the fragment.
        Helper::assertSame('%23%E2%82%AC?/b%61r', $uri->getFragment());
        Helper::assertSame('#%23%E2%82%AC?/b%61r', $uri->__toString());
    }

    public function testAllowsForRelativeUri(): void
    {
        $uri = (new Uri())->withPath('foo');
        Helper::assertSame('foo', $uri->getPath());
        Helper::assertSame('foo', $uri->__toString());
    }

    public function testRelativePathAndAuthorityThrowsException(): void
    {
        // concatenating a relative path with a host doesn't work: "//example.comfoo" would be wrong
        expect(() ==> (new Uri())->withHost('example.com')->withPath('foo'))->toThrow(\InvalidArgumentException::class, 'The path of a URI with an authority must start with a slash "/" or be empty');
    }

    public function testPathStartingWithTwoSlashesAndNoAuthorityIsInvalid(): void
    {
        expect(() ==> // URI "//foo" would be interpreted as network reference and thus change the original path to the host
        (new Uri())->withPath('//foo'))->toThrow(\InvalidArgumentException::class, 'The path of a URI without an authority must not start with two slashes "//"');
    }

    public function testPathStartingWithTwoSlashes(): void
    {
        $uri = new Uri('http://example.org//path-not-host.com');
        Helper::assertSame('//path-not-host.com', $uri->getPath());

        $uri = $uri->withScheme('');
        Helper::assertSame('//example.org//path-not-host.com', $uri->__toString()); // This is still valid
        expect(() ==> $uri->withHost(''))->toThrow(\InvalidArgumentException::class); // Now it becomes invalid
    }

    public function testRelativeUriWithPathBeginngWithColonSegmentIsInvalid(): void
    {
        expect(() ==> (new Uri())->withPath('mailto:foo'))->toThrow(\InvalidArgumentException::class, 'A relative URI must not have a path beginning with a segment containing a colon');
    }

    public function testRelativeUriWithPathHavingColonSegment(): void
    {
        $uri = (new Uri('urn:/mailto:foo'))->withScheme('');
        Helper::assertSame('/mailto:foo', $uri->getPath());

        expect(() ==> (new Uri('urn:mailto:foo'))->withScheme(''))->toThrow(\InvalidArgumentException::class);
    }

    public function testDefaultReturnValuesOfGetters(): void
    {
        $uri = new Uri();

        Helper::assertSame('', $uri->getScheme());
        Helper::assertSame('', $uri->getAuthority());
        Helper::assertSame('', $uri->getUserInfo());
        Helper::assertSame('', $uri->getHost());
        Helper::assertNull($uri->getPort());
        Helper::assertSame('', $uri->getPath());
        Helper::assertSame('', $uri->getQuery());
        Helper::assertSame('', $uri->getFragment());
    }

    public function testImmutability(): void
    {
        $uri = new Uri();

        Helper::assertNotSame($uri, $uri->withScheme('https'));
        Helper::assertNotSame($uri, $uri->withUserInfo('user', 'pass'));
        Helper::assertNotSame($uri, $uri->withHost('example.com'));
        Helper::assertNotSame($uri, $uri->withPort(8080));
        Helper::assertNotSame($uri, $uri->withPath('/path/123'));
        Helper::assertNotSame($uri, $uri->withQuery('q=abc'));
        Helper::assertNotSame($uri, $uri->withFragment('test'));
    }

    public function testSpecialCharsOfUserInfo(): void
    {
        // The `userInfo` must always be URL-encoded.
        $uri = (new Uri())->withUserInfo('foo@bar.com', 'pass#word');
        Helper::assertSame('foo%40bar.com:pass%23word', $uri->getUserInfo());

        // The `userInfo` can already be URL-encoded: it should not be encoded twice.
        $uri = (new Uri())->withUserInfo('foo%40bar.com', 'pass%23word');
        Helper::assertSame('foo%40bar.com:pass%23word', $uri->getUserInfo());
    }

    public function testInternationalizedDomainName(): void
    {
        $uri = new Uri('https://яндекс.рф');
        Helper::assertSame('яндекс.рф', $uri->getHost());

        $uri = new Uri('https://яндекAс.рф');
        Helper::assertSame('яндекaс.рф', $uri->getHost());
    }

    public function testIPv6Host(): void
    {
        $uri = new Uri('https://[2a00:f48:1008::212:183:10]');
        Helper::assertSame('[2a00:f48:1008::212:183:10]', $uri->getHost());

        $uri = new Uri('http://[2a00:f48:1008::212:183:10]:56?foo=bar');
        Helper::assertSame('[2a00:f48:1008::212:183:10]', $uri->getHost());
        Helper::assertSame(56, $uri->getPort());
        Helper::assertSame('foo=bar', $uri->getQuery());
    }
}

class ExtendedUriTest extends Uri
{
}
