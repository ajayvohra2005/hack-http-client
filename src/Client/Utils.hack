namespace HackHttp\Client;

use namespace HackHttp\Message as HM;

use HackHttp\Client\Exception\InvalidArgumentException;
use HackHttp\Client\Handler\CurlHandler;
use HackHttp\Client\Handler\CurlMultiHandler;
use HackHttp\Client\Handler\Proxy;
use HackHttp\Message\UriInterface;

use HackPromises\PromiseInterface;
use HackHttp\Message\RequestInterface;

use namespace HH\Lib\C;
use namespace HH\Lib\Dict;
use namespace HH\Lib\File;
use namespace HH;

final class Utils
{
   
    /**
     * Parses an vec<string> of header lines into dict<string, vec<string>>.
     *
     * @param vec<string> $lines Header lines array of strings in the following
     *                        format: "Name: Value"
     * @return dict<string, vec<string>>
     */
    public static function headersFromLines(vec<string> $lines): dict<string, vec<string>>
    {
        $headers = dict[];

        foreach ($lines as $line) {
            $parts = \explode(':', $line, 2);
            $header_name = \trim($parts[0]);
            $header_vec = HH\idx($headers, $header_name);
            if($header_vec is null) {
                $header_vec = vec<string>[];
            }
            $header_vec[] = isset($parts[1]) ? \trim($parts[1]) : '';
            $headers[$header_name] = $header_vec;
        }

        return $headers;
    }
      

    /**
     * Chooses and creates a default handler to use based on the environment.
     *
     * The returned handler is not wrapped by any default middlewares.
     *
     * @throws \RuntimeException if no viable Handler is available.
     *
     * @return RequestHandlerCallable Returns the best handler for the given system.
     */
    public static function chooseHandler(): RequestHandlerCallable
    {
        $handler = null;
        $sync_handler = (RequestInterface $request, dict<arraykey,  mixed> $options): PromiseInterface ==> {
            $ch = new CurlHandler($options);
            return $ch->handle($request, $options);
        };

        $default_handler = (RequestInterface $request, dict<arraykey,  mixed> $options): PromiseInterface ==> {
            $mh = new CurlMultiHandler($options);
            return $mh->handle($request, $options);
        };

        
        return Proxy::wrapSync($default_handler, $sync_handler);
    }

    /**
     * Get the default User-Agent string
     */
    public static function defaultUserAgent(): string
    {
        return 'hack-http-client';
    }

    /**
     * Creates an associative array of lowercase header names to the actual
     * header casing.
     */
    public static function normalizeHeaderKeys(dict<string, mixed> $headers): dict<string, mixed>
    {
        $result = dict[];
        foreach (\array_keys($headers) as $key) {
            $result[\strtolower($key)] = $key;
        }

        return $result;
    }

    /**
     * Returns true if the provided host matches any of the no proxy areas.
     *
     * This method will strip a port from the host if it is present. Each pattern
     * can be matched with an exact match (e.g., "foo.com" == "foo.com") or a
     * partial match: (e.g., "foo.com" == "baz.foo.com" and ".foo.com" ==
     * "baz.foo.com", but ".foo.com" != "foo.com").
     *
     * Areas are matched in the following cases:
     * 1. "*" (without quotes) always matches any hosts.
     * 2. An exact match.
     * 3. The area starts with "." and the area is the last part of the host. e.g.
     *    '.mit.edu' will match any host that ends with '.mit.edu'.
     *
     * @param string   $host         Host to check against the patterns.
     * @param vec<string> $noProxyArray An array of host patterns.
     *
     * @throws InvalidArgumentException
     */
    public static function isHostInNoProxy(string $host, vec<string> $noProxyArray): bool
    {
        if (\strlen($host) === 0) {
            throw new \InvalidArgumentException('Empty host provided');
        }

        // Strip port if present.
        $host = \explode(':', $host, 2)[0];

        foreach ($noProxyArray as $area) {
            // Always match on wildcards.
            if ($area === '*') {
                return true;
            }

            if (!$area) {
                // Don't match on empty values.
                continue;
            }

            if ($area === $host) {
                // Exact matches.
                return true;
            }
            // Special match if the area when prefixed with ".". Remove any
            // existing leading "." and add a new leading ".".
            $area = '.' . \ltrim($area, '.');
            if (\substr($host, -(\strlen($area))) === $area) {
                return true;
            }
        }

        return false;
    }

    /**
     * Wrapper for json_decode that throws when an error occurs.
     *
     * @param string $json    JSON data to parse
     * @param bool   $assoc   When true, returned objects will be converted
     *                        into associative arrays.
     * @param int    $depth   User specified recursion depth.
     * @param int    $options Bitmask of JSON decode options.
     *
     * @return mixed
     *
     * @throws InvalidArgumentException if the JSON cannot be decoded.
     *
     * @link https://www.php.net/manual/en/function.json-decode.php
     */
    public static function jsonDecode(string $json, bool $assoc = false, int $depth = 512, int $options = 0): mixed
    {
        $last_error = null;

        $data = \json_decode_with_error($json, inout $last_error, $assoc, $depth, $options);
        if ($last_error is nonnull && \JSON_ERROR_NONE !== $last_error[0]) {
            throw new \InvalidArgumentException('json_decode error: ' . $last_error[1]);
        }

        return $data;
    }

    /**
     * Wrapper for JSON encoding that throws when an error occurs.
     *
     * @param mixed $value   The value being encoded
     * @param int   $options JSON encode option bitmask
     * @param int   $depth   Set the maximum depth. Must be greater than zero.
     *
     * @throws InvalidArgumentException if the JSON cannot be encoded.
     *
     * @link https://www.php.net/manual/en/function.json-encode.php
     */
    public static function jsonEncode(mixed $value, int $options = 0, int $depth = 512): string
    {
        $last_error = null;
        $json = \json_encode_with_error($value, inout $last_error, $options, $depth);
        

        if ($last_error is nonnull && \JSON_ERROR_NONE !== $last_error[0]) {
            throw new \InvalidArgumentException('json_encode error: ' . $last_error[1]);
        }

        /** @var string */
        return $json;
    }

    /**
     *
     * @return float Return current Unix timestamp with microseconds
     *
     * @internal
     */
    public static function currentTime(): float
    {
        return  \microtime(true);
    }

    /**
     * @throws \InvalidArgumentException
     *
     * @internal
     */
    public static function idnUriConvert(UriInterface $uri, int $options = 0): UriInterface
    {
        if ($uri->getHost()) {
            $asciiHost = self::idnToAsci($uri->getHost(), $options);
            if ($asciiHost === false) {
                throw new \InvalidArgumentException("IDN to Acii Host conversion failed");
            }
            if ($uri->getHost() !== $asciiHost) {
                // Replace URI only if the ASCII version is different
                if($asciiHost is string) {
                    $uri = $uri->withHost($asciiHost);
                }
            }
        }

        return $uri;
    }

    /**
     * @internal
     */
    public static function getenv(string $name): ?string
    {
        $value = \getenv($name);

        if ($value !== false && $value is nonnull) {
            return (string) $value;
        }

        return null;
    }

    /**
     * @return mixed
     */
    private static function idnToAsci(string $domain, int $options): mixed
    {
        return \idn_to_ascii($domain, $options, \INTL_IDNA_VARIANT_UTS46);
    }

}
