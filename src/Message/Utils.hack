namespace HackHttp\Message;

use namespace HH;
use namespace HH\Lib\C;
use namespace HH\Lib\Str;
use namespace HH\Lib\Vec;
use namespace HH\Lib\Dict;
use namespace HH\Lib\File;
use namespace HH\Lib\OS;
use namespace HH\Lib\IO;

final class Utils
{
    /**
     * Remove the items given by the keys, case insensitively from the data.
     *
     * @param dict<arraykey, mixed> $keys
     */
    public static function caselessRemove(vec<string> $keys, dict<arraykey, mixed> $data): dict<string, mixed>
    {
        $result = dict[];

        $map_cb = (string $v): string ==> \strtolower($v);
        $keys = Vec\map($keys, $map_cb);

        foreach ($data as $k => $v) {
            if ($k is string && !\in_array(\strtolower($k), $keys)) {
                $result[$k] = $v;
            }
        }

        return $result;
    }

    /**
     * Copy the contents of a stream into another stream until the given number
     * of bytes have been read.
     *
     * @param StreamInterface $source Stream to read from
     * @param StreamInterface $dest   Stream to write to
     * @param int             $maxLen Maximum number of bytes to read. Pass -1
     *                                to read the entire stream.
     *
     * @throws \RuntimeException on error.
     */
    public static function copyToStream(StreamInterface $source, StreamInterface $dest, int $maxLen = -1): void
    {
        $bufferSize = 8192;

        if ($maxLen === -1) {
            while (!$source->eof()) {
                if (!$dest->write($source->read($bufferSize))) {
                    break;
                }
            }
        } else {
            $remaining = $maxLen;
            while ($remaining > 0 && !$source->eof()) {
                $buf = $source->read(\min($bufferSize, $remaining));
                $len = \strlen($buf);
                if (!$len) {
                    break;
                }
                $remaining -= $len;
                $dest->write($buf);
            }
        }
    }

    /**
     * Copy the contents of a stream into a string until the given number of
     * bytes have been read.
     *
     * @param StreamInterface $stream Stream to read
     * @param int             $maxLen Maximum number of bytes to read. Pass -1
     *                                to read the entire stream.
     *
     * @throws \RuntimeException on error.
     */
    public static function copyToString(StreamInterface $stream, int $maxLen = -1): string
    {
        $buffer = '';

        if ($maxLen === -1) {
            while (!$stream->eof()) {
                $buf = $stream->read(1048576);
                if ($buf === '') {
                    break;
                }
                $buffer .= $buf;
            }
            return $buffer;
        }

        $len = 0;
        while (!$stream->eof() && $len < $maxLen) {
            $buf = $stream->read($maxLen - $len);
            if ($buf === '') {
                break;
            }
            $buffer .= $buf;
            $len = \strlen($buffer);
        }

        return $buffer;
    }

    /**
     * Calculate a hash of a stream.
     *
     * This method reads the entire stream to calculate a rolling hash, based
     * on PHP's `hash_init` functions.
     *
     * @param StreamInterface $stream    Stream to calculate the hash for
     * @param string          $algo      Hash algorithm (e.g. md5, crc32, etc)
     * @param bool            $rawOutput Whether or not to use raw output
     *
     * @throws \RuntimeException on error.
     */
    public static function hash(StreamInterface $stream, string $algo, bool $rawOutput = false): string
    {
        $pos = $stream->tell();

        if ($pos > 0) {
            $stream->rewind();
        }

        $ctx = \hash_init($algo);
        while (!$stream->eof()) {
            \hash_update($ctx, $stream->read(1048576));
        }

        $out = \hash_final($ctx, (bool) $rawOutput);
        $stream->seek($pos);

        return $out;
    }

    /**
     * Clone and modify a request with the given changes.
     *
     * This method is useful for reducing the number of clones needed to mutate
     * a message.
     *
     * The changes can be one of:
     * - method: (string) Changes the HTTP method.
     * - set_headers: dict<string, mixed> Sets the given headers.
     * - remove_headers: vec<string> Remove the given headers.
     * - body: (mixed) Sets the given body.
     * - uri: (UriInterface) Set the URI.
     * - query: (string) Set the query string value of the URI.
     * - version: (string) Set the protocol version.
     *
     * @param RequestInterface $request Request to clone and modify.
     * @param dict<string, mixed>            $changes Changes to apply.
     */
    public static function modifyRequest(RequestInterface $request, dict<string, mixed> $changes): RequestInterface
    {
        if (C\count($changes) == 0) {
            return $request;
        }

        $headers = $request->getHeaders();

        if (!\isset($changes['uri'])) {
            $uri = $request->getUri();
        } else {
            // Remove the host header if one is on the URI
            $changes_uri = HH\idx($changes,'uri');
            if($changes_uri is UriInterface) {
                $host = $changes_uri->getHost();
                if ($host is string) {
                    $headers = self::caselessRemove(vec["Host"], $headers);
                    $set_headers = HH\idx($changes,'set_headers');
                    if($set_headers is dict<_,_>) {
                        $set_headers['Host'] = $host;
                    
                        $port = $changes_uri->getPort();

                        if ($port is int) {
                            $standardPorts = dict['http' => 80, 'https' => 443];
                            $scheme = $changes_uri->getScheme();
                            if (\isset($standardPorts[$scheme]) && $port != $standardPorts[$scheme]) {
                                $set_headers_host = HH\idx($set_headers,'Host');
                                if($set_headers_host is string) {
                                    $set_headers['Host'] = $set_headers_host.':' . $port;
                                }
                            }
                        }

                        $changes['set_headers'] = $set_headers;
                    }
                }
            }
            $uri = HH\idx($changes,'uri');
        }

        $remove_headers = HH\idx($changes,'remove_headers');
        if ($remove_headers is vec<_>) {
            $headers = self::caselessRemove(self::filterTraversable<string>($remove_headers), $headers);
        }

        $set_headers = HH\idx($changes,'set_headers');
        if($set_headers is dict<_,_>) {
            $set_headers = self::filterHeaders($set_headers);
            $headers = self::caselessRemove(Vec\keys($set_headers), $headers);
            $headers = Dict\merge($set_headers, $headers);
        }
        

        if (\isset($changes['query'])) {
            $query = HH\idx($changes, 'query');
            if($uri is UriInterface && $query is string) {
                $uri = $uri->withQuery($query);
            }
        }

        $c_method = HH\idx($changes, 'method');
        $c_body = HH\idx($changes, 'body');
        $c_version = HH\idx($changes, 'version');

        if($uri is nonnull) {
            return new Request(
                $c_method is string ? $c_method: $request->getMethod(),
                $uri,
                Utils::filterHeaders($headers),
                $c_body ?? $request->getBody(),
                $c_version is string ? $c_version :  $request->getProtocolVersion()
            );
        } else {
            throw new \RuntimeException("Uri is null");
        }
    }

    /**
     * Read a line from the stream up to the maximum allowed buffer length.
     *
     * @param StreamInterface $stream    Stream to read from
     * @param int|null        $maxLength Maximum buffer length
     * @return string         string read from stream
     */
    public static function readLine(StreamInterface $stream, ?int $maxLength = null): string
    {
        $buffer = '';
        $size = 0;

        while (!$stream->eof()) {
            $byte = $stream->read(1);
            if ('' === $byte) {
                return $buffer;
            }
            ++$size;
            $buffer .= $byte;
            // Break when a new line is found or the max length - 1 is reached
            if ($byte === "\n" || ($maxLength is int && ($size === $maxLength - 1) )) {
                break;
            }
        }

        return $buffer;
    }

    /**
     * Create a new stream based on the input type.
     *
     * Options is an associative array that can contain the following keys:
     * - metadata: Array of custom metadata.
     * - size: Size of the stream.
     *
     * This method accepts the following `$resource` types:
     * - `HackHttp\Message\StreamInterface`: Returns the value as-is.
     * - `string`: Creates a stream object that uses the given string as the contents.
     * - `Iterator`: If the provided value implements `Iterator`, then a read-only
     *   stream object will be created that wraps the given iterable. Each time the
     *   stream is read from, data from the iterator will fill a buffer and will be
     *   continuously called until the buffer is equal to the requested read size.
     *   Subsequent read calls will first read from the buffer and then call `next`
     *   on the underlying iterator until it is exhausted.
     * - `object` with `__toString()`: If the object has the `__toString()` method,
     *   the object will be cast to a string and then a stream will be returned that
     *   uses the string value.
     * - `NULL`: When `null` is passed, an empty stream object is returned.
     * - `callable` When a callable is passed, a read-only stream object will be
     *   created that invokes the given callable. The callable is invoked with the
     *   number of suggested bytes to read. The callable can return any number of
     *   bytes, but MUST return `false` when there is no more data to return. The
     *   stream object that wraps the callable will invoke the callable until the
     *   number of requested bytes are available. Any additional bytes will be
     *   buffered and used in subsequent reads.
     *
     * @param mixed $resource Entity body data
     * @param ?StreamOptions   $options  Additional options
     *
     * @throws \InvalidArgumentException if the $resource arg is not valid.
     */

    public static function streamFor(mixed $resource, ?StreamOptions $options=null): StreamInterface
    {
        if ($resource is string || 
            $resource is int || $resource is float || $resource is bool) {
            $str_value = (string)$resource;
            if($options is null) {
                $options = shape('size' => Str\length($str_value), 'metadata' => null);
            }
            $handle = new IO\MemoryHandle($str_value);
            return new Stream($handle, $options);
        } elseif ($resource is HasToStringInterface) {
            $str_value = $resource->__toString();
            if($options is null) {
                $options = shape('size' => Str\length($str_value), 'metadata' => null);
            }
            $handle = new IO\MemoryHandle($str_value);
            return new Stream($handle, $options);
        } elseif($resource is IO\Handle) {
            return new Stream($resource, $options);
        } elseif($resource is StreamInterface) {
            return $resource;
        } elseif ($resource is HH\Iterator<_>) {
            $func = self::createPumpFunction($resource);
            return new PumpStream($func, $options);
        } elseif ($resource is null) {
            $handle = self::getFileHandle();
            if($handle is File\Handle) {
                return new Stream($handle, $options);
            }
         }

        throw new \InvalidArgumentException('Invalid resource type');
    }

    private static function createPumpFunction(HH\Iterator<mixed> $iterator): PumpFunction
    {
        $f = (?int $length): ?string ==> {

            if( !$iterator->valid() ){
                return null;
            }
            $value = $iterator->current();
            $iterator->next();
            return Utils::is_implicit_string($value) ? (string)$value: null;
        };

        return $f;
    }

    /**
     * Safely opens a File\Handle resource using a filename.
     *
     * @param ?string $path File to open
     * @param ?File\WriteMode $mode     Mode used to open the file
     *
     * @return ?File\Handle  file handle
     *
     * @throws \RuntimeException if the file cannot be opened
     */
    public static function getFileHandle(?string $path=null, ?File\WriteMode $mode=null): ?File\Handle
    {
        $handle = null;

        if($path is string) {
            if($mode is nonnull) {
                $handle = File\open_read_write($path, $mode);
            } else {
                $handle = File\open_read_only($path);
            }
        } else {
            $tmp_dir = \sys_get_temp_dir();
            $path = OS\mkstemp("{$tmp_dir}/hack-http-XXXXXX")[1];
            if($path is string) {
                $handle = File\open_read_write($path);
            }
        }
        

        return $handle;
    }

    /**
     * Returns a UriInterface for the given value.
     *
     * This function accepts a string or UriInterface and returns a
     * UriInterface for the given value. If the value is already a
     * UriInterface, it is returned as-is.
     *
     * @param mixed $uri
     *
     * @return UriInterface
     * @throws \InvalidArgumentException
     */
    public static function uriFor(mixed $uri): UriInterface
    {
        if ($uri is UriInterface) {
            return $uri;
        }

        if ($uri is string) {
            return new Uri($uri);
        }

        throw new \InvalidArgumentException('URI must be a string or UriInterface');
    }

    public static function filterKeyedTraversable<<<__Enforceable>> reify  Tv>(KeyedTraversable<arraykey, Tv> $container): dict<arraykey, Tv> 
    {
        $ret = dict<arraykey, Tv>[];

        foreach ($container as $key => $value) {
            if ($value is Tv) {
                $ret[$key] = $value;
            }
        }

        return $ret;
    }

    public static function filterDictStringKeys(KeyedTraversable<arraykey, mixed> $container): dict<string, mixed> 
    {
        $ret = dict<string, mixed>[];

        foreach ($container as $key => $value) {
            if ($key is string) {
                $ret[$key] = $value;
            }
        }

        return $ret;
    }

    public static function filterHeaders(dict<arraykey, mixed> $headers): dict<string, vec<string>> {
        $ret = dict<string, vec<string>>[];

        foreach ($headers as $key => $value) {
            if ($key is string) {
                if($value is vec<_>) {
                    $vec_string = self::filterTraversable<string>($value);
                    $ret[$key] = $vec_string;
                } else if(self::is_implicit_string($value)) {
                    $ret[$key] = vec[(string)$value];
                }
                
            }
        }

        return $ret;
    }

     public static function filterMultipart(vec<mixed> $multipart): vec<dict<string, mixed>> 
     {
        $safe_multipart = vec<dict<string, mixed>>[];

        foreach ($multipart as $part) {
            if($part is dict<_,_>) {
                $safe_part = dict<string, mixed>[];
                foreach ($part as $key => $value) {
                    if($key is string) {
                        $safe_part[$key] = $value;
                    }
                }
                $safe_multipart[] = $safe_part;
            }
        }
        return $safe_multipart;
    }

    public static function filterTraversable<<<__Enforceable>> reify  Tv>(Traversable<mixed> $container): vec<Tv> 
    {
        $ret = vec<Tv>[];

        foreach ($container as $value) {
            if ($value is Tv) {
                $ret[] = $value;
            }
        }

        return $ret;
    }

    public static function is_implicit_string(mixed $value): bool
    {
        try {
            $cast_as_string = (string)$value;
            return true;
        } catch(\TypeAssertionException $e){
            return false;
        }
    }
}
