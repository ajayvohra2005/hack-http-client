namespace HackHttp\Message;

use namespace HH\Lib\File;
use namespace HH\Lib\Str;

/**
 * Stream decorator that can cache previously read bytes from a sequentially
 * read stream.
 */
final class CachingStream implements StreamInterface
{
    use StreamDecoratorTrait;

    /** @var StreamInterface Stream being wrapped */
    private StreamInterface $cachedStream;

    /** @var int Number of bytes to skip reading due to a write on the buffer */
    private int $skipReadBytes = 0;

    /**
     * We will treat the buffer object as the body of the stream
     *
     * @param StreamInterface $cached_stream Stream to cache. The cursor is assumed to be at the beginning of the stream.
     * @param StreamInterface $target Optionally specify where data is cached
     */
    public function __construct(
        StreamInterface $cached_stream,
        ?StreamInterface $target = null
    ) {
        $this->cachedStream = $cached_stream;
        
        if($target is null) {
            $handle = Utils::getFileHandle();
            if($handle is File\Handle) {
                $this->stream = new Stream($handle);
            } else {
                throw new \RuntimeException("Failed to create the stream to cache data");
            }
        } else {
            $this->stream = $target;
        }
    }

    public function getSize(): ?int
    {
        $_stream = $this->stream;
        if($_stream is nonnull) {
            return \max($_stream->getSize(), $this->cachedStream->getSize());
        } else {
            return null;
        }
    }

    public function rewind(): void
    {
        $this->seek(0);
    }

    public function seek(int $offset, int $whence = \SEEK_SET): void
    {
        $_stream = $this->stream;
        if($_stream is null) {
            return;
        }

        if ($whence === \SEEK_SET) {
            $seek_offset = $offset;
        } elseif ($whence === \SEEK_CUR) {
            $seek_offset = $offset + $this->tell();
        } elseif ($whence === \SEEK_END) {
            $size = $this->cachedStream->getSize();
            if ($size === null) {
                $size = $this->cacheEntireStream();
            }
            $seek_offset = $size + $offset;
        } else {
            throw new \InvalidArgumentException('Invalid whence');
        }

        $stream_size = $_stream->getSize();
        if($stream_size is int) {
            $diff = $seek_offset - $stream_size;
            if ($diff > 0) {
                // Read the cachedStream until we have read in at least the amount
                // of bytes requested, or we reach the end of the file.
                while ($diff > 0 && !$this->cachedStream->eof()) {
                    $this->read($diff);
                    $stream_size = $_stream->getSize();
                    if($stream_size is int) {
                        $diff = $seek_offset - $stream_size;
                    } else {
                        throw new \RuntimeException("Data stream size for cached data is not an int");
                    }
                }
            } else {
                // We can just do a normal seek since we've already seen this byte.
                $_stream->seek($seek_offset);
            } 
        } else {
            throw new \RuntimeException("Data stream size for cached data is not an int");
        }
    }

    public function read(?int $length): string
    {
        if($length is null) {
            return $this->getContents();
        }

        $_stream = $this->stream;
        if($_stream is null) {
            return '';
        }

        // Perform a regular read on any previously read data from the buffer
        $data = $_stream->read($length);
        $remaining = $length - \strlen($data);

        // More data was requested so read from the remote stream
        if ($remaining) {
            // If data was written to the buffer in a position that would have
            // been filled from the remote stream, then we must skip bytes on
            // the remote stream to emulate overwriting bytes from that
            // position. This mimics the behavior of other PHP stream wrappers.
            $remoteData = $this->cachedStream->read(
                $remaining + $this->skipReadBytes
            );

            if ($this->skipReadBytes) {
                $len = \strlen($remoteData);
                $remoteData = Str\slice($remoteData, $this->skipReadBytes);
                $this->skipReadBytes = \max(0, $this->skipReadBytes - $len);
            }

            $data .= $remoteData;
            $_stream->write($remoteData);
        }

        return $data;
    }

    public function write(string $string): int
    {
        $_stream = $this->stream;
        if($_stream is null) {
            return 0;
        }

        // When appending to the end of the currently read stream, you'll want
        // to skip bytes from being read from the remote stream to emulate
        // other stream wrappers. Basically replacing bytes of data of a fixed
        // length.
        $overflow = (\strlen($string) + $this->tell()) - $this->cachedStream->tell();
        if ($overflow > 0) {
            $this->skipReadBytes += $overflow;
        }

        return $_stream->write($string);
    }

    public function eof(): bool
    {
        $_stream = $this->stream;
        if($_stream is null) {
            return true;
        }

        return $_stream->eof() && $this->cachedStream->eof();
    }

    /**
     * Close both the remote stream and buffer stream
     */
    public function close(): void
    {
        $_stream = $this->stream;
        if($_stream is nonnull) {
            $this->cachedStream->close();
            $_stream->close();
        }
    }

    private function cacheEntireStream(): int
    {
        $_stream = $this->stream;
        if($_stream is nonnull) {
            Utils::copyToStream($this->cachedStream, $_stream);
            return $this->tell();
        }

        return 0;
    }
}
