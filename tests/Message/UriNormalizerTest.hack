namespace HackHttp\Tests\Message;

use HackHttp\Tests\Helper;

use HackHttp\Message\Uri;
use HackHttp\Message\UriNormalizer;
use function Facebook\FBExpect\expect;
use type Facebook\HackTest\{HackTest, DataProvider};
use HackHttp\Message\UriInterface;

/**
 * @covers HackHttp\Message\UriNormalizer
 */
class UriNormalizerTest extends HackTest
{
    public function testCapitalizePercentEncoding(): void
    {
        $actualEncoding = 'a%c2%7A%5eb%25%fa%fA%Fa';
        $expectEncoding = 'a%C2%7A%5Eb%25%FA%FA%FA';
        $uri = (new Uri())->withPath("/$actualEncoding")->withQuery($actualEncoding);

        Helper::assertSame("/$actualEncoding?$actualEncoding", $uri->__toString(), 'Not normalized automatically beforehand');

        $normalizedUri = UriNormalizer::normalize($uri, UriNormalizer::CAPITALIZE_PERCENT_ENCODING);

        Helper::assertInstanceOf(UriInterface::class, $normalizedUri);
        Helper::assertSame("/$expectEncoding?$expectEncoding", $normalizedUri->__toString());
    }

    <<DataProvider('getUnreservedCharacters')>>
    public function testDecodeUnreservedCharacters(string $char): void
    {
        $percentEncoded = '%' . \bin2hex($char);
        // Add encoded reserved characters to test that those are not decoded and include the percent-encoded
        // unreserved character both in lower and upper case to test the decoding is case-insensitive.
        $encodedChars = $percentEncoded . '%2F%5B' . \strtoupper($percentEncoded);
        $uri = (new Uri())->withPath("/$encodedChars")->withQuery($encodedChars);

        Helper::assertSame("/$encodedChars?$encodedChars", $uri->__toString(), 'Not normalized automatically beforehand');

        $normalizedUri = UriNormalizer::normalize($uri, UriNormalizer::DECODE_UNRESERVED_CHARACTERS);

        Helper::assertInstanceOf(UriInterface::class, $normalizedUri);
        Helper::assertSame("/$char%2F%5B$char?$char%2F%5B$char", $normalizedUri->__toString());
    }

    public function getUnreservedCharacters(): vec<(string)>
    {
        $unreservedChars = \array_merge(\range('a', 'z'), \range('A', 'Z'), \range(0, 9), vec['-', '.', '_', '~']);

        return vec(\array_map( (mixed $char): (string) ==> {
            if($char is arraykey) {
                return tuple((string)$char);
            } 

            return tuple('');
        }, $unreservedChars));
    }

    <<DataProvider('getEmptyPathTestCases')>>
    public function testConvertEmptyPath(string $uri, string $expected): void
    {
        $normalizedUri = UriNormalizer::normalize(new Uri($uri), UriNormalizer::CONVERT_EMPTY_PATH);

        Helper::assertInstanceOf(UriInterface::class, $normalizedUri);
        Helper::assertSame($expected, $normalizedUri->__toString());
    }

    public function getEmptyPathTestCases(): vec<(string, string)>
    {
        return vec[
            tuple('http://example.org', 'http://example.org/'),
            tuple('https://example.org', 'https://example.org/'),
            tuple('urn://example.org', 'urn://example.org'),
        ];
    }

    public function testRemoveDefaultHost(): void
    {
        $uri = new Uri('file://localhost/myfile');
        $normalizedUri = UriNormalizer::normalize($uri, UriNormalizer::REMOVE_DEFAULT_HOST);

        Helper::assertInstanceOf(UriInterface::class, $normalizedUri);
        Helper::assertSame('file:///myfile', $normalizedUri->__toString());
    }

    public function testRemoveDotSegments(): void
    {
        $uri = new Uri('http://example.org/../a/b/../c/./d.html');
        $normalizedUri = UriNormalizer::normalize($uri, UriNormalizer::REMOVE_DOT_SEGMENTS);

        Helper::assertInstanceOf(UriInterface::class, $normalizedUri);
        Helper::assertSame('http://example.org/a/c/d.html', $normalizedUri->__toString());
    }

    public function testRemoveDotSegmentsOfAbsolutePathReference(): void
    {
        $uri = new Uri('/../a/b/../c/./d.html');
        $normalizedUri = UriNormalizer::normalize($uri, UriNormalizer::REMOVE_DOT_SEGMENTS);

        Helper::assertInstanceOf(UriInterface::class, $normalizedUri);
        Helper::assertSame('/a/c/d.html', $normalizedUri->__toString());
    }

    public function testRemoveDotSegmentsOfRelativePathReference(): void
    {
        $uri = new Uri('../c/./d.html');
        $normalizedUri = UriNormalizer::normalize($uri, UriNormalizer::REMOVE_DOT_SEGMENTS);

        Helper::assertInstanceOf(UriInterface::class, $normalizedUri);
        Helper::assertSame('../c/./d.html', $normalizedUri->__toString());
    }

    public function testRemoveDuplicateSlashes(): void
    {
        $uri = new Uri('http://example.org//foo///bar/bam.html');
        $normalizedUri = UriNormalizer::normalize($uri, UriNormalizer::REMOVE_DUPLICATE_SLASHES);

        Helper::assertInstanceOf(UriInterface::class, $normalizedUri);
        Helper::assertSame('http://example.org/foo/bar/bam.html', $normalizedUri->__toString());
    }

    public function testSortQueryParameters(): void
    {
        $uri = new Uri('?lang=en&article=fred');
        $normalizedUri = UriNormalizer::normalize($uri, UriNormalizer::SORT_QUERY_PARAMETERS);

        Helper::assertInstanceOf(UriInterface::class, $normalizedUri);
        Helper::assertSame('?article=fred&lang=en', $normalizedUri->__toString());
    }

    public function testSortQueryParametersWithSameKeys(): void
    {
        $uri = new Uri('?a=b&b=c&a=a&a&b=a&b=b&a=d&a=c');
        $normalizedUri = UriNormalizer::normalize($uri, UriNormalizer::SORT_QUERY_PARAMETERS);

        Helper::assertInstanceOf(UriInterface::class, $normalizedUri);
        Helper::assertSame('?a&a=a&a=b&a=c&a=d&b=a&b=b&b=c', $normalizedUri->__toString());
    }

    <<DataProvider('getEquivalentTestCases')>>
    public function testIsEquivalent(string $uri1, string $uri2, bool $expected): void
    {
        $equivalent = UriNormalizer::isEquivalent(new Uri($uri1), new Uri($uri2));

        Helper::assertSame($expected, $equivalent);
    }

    public function getEquivalentTestCases(): vec<(string, string, bool)>
    {
        return vec[
            tuple('http://example.org', 'http://example.org', true),
            tuple('hTTp://eXaMpLe.org', 'http://example.org', true),
            tuple('http://example.org/path?#', 'http://example.org/path', true),
            tuple('http://example.org:80', 'http://example.org/', true),
            tuple('http://example.org/../a/.././p%61th?%7a=%5e', 'http://example.org/path?z=%5E', true),
            tuple('https://example.org/', 'http://example.org/', false),
            tuple('https://example.org/', '//example.org/', false),
            tuple('//example.org/', '//example.org/', true),
            tuple('file:/myfile', 'file:///myfile', true),
            tuple('file:///myfile', 'file://localhost/myfile', true),
        ];
    }
}
