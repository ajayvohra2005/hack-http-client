namespace HackHttp\Message;

use namespace HH\Lib\Str;

/**
 * Provides a buffer stream that can be written to to fill a buffer, and read
 * from to remove bytes from the buffer.
 *
 * This stream returns a "hwm" metadata value that tells upstream consumers
 * what the configured high water mark of the stream is, or the maximum
 * preferred size of the buffer.
 */
final class BufferStream implements StreamInterface
{
    /** @var int */
    private int $hwm;

    /** @var string */
    private string $buffer = '';

    /**
     * @param int $hwm High water mark, representing the preferred maximum
     *                 buffer size. If the size of the buffer exceeds the high
     *                 water mark, then calls to write will continue to succeed
     *                 but will return 0 to inform writers to slow down
     *                 until the buffer has been drained by reading from it.
     */
    public function __construct(int $hwm = 16384)
    {
        $this->hwm = $hwm;
    }

    public function __toString(): string
    {
        return $this->getContents();
    }

    public function getContents(): string
    {
        $buffer = $this->buffer;
        $this->buffer = '';

        return $buffer;
    }

    public function close(): void
    {
        $this->buffer = '';
    }

    public function detach(): void
    {
        $this->close();
    }

    public function getSize(): ?int
    {
        return \strlen($this->buffer);
    }

    public function isReadable(): bool
    {
        return true;
    }

    public function isWritable(): bool
    {
        return true;
    }

    public function isSeekable(): bool
    {
        return false;
    }

    public function rewind(): void
    {
        throw new \RuntimeException('Cannot rewind a BufferStream');
    }

    public function seek(int $offset, int $whence = \SEEK_SET): void
    {
        throw new \RuntimeException('Cannot seek a BufferStream');
    }

    public function eof(): bool
    {
        return \strlen($this->buffer) === 0;
    }

    public function tell(): int
    {
        throw new \RuntimeException('Cannot determine the position of a BufferStream');
    }

    /**
     * Reads data from the buffer.
     */
    public function read(?int $length): string
    {
        $result = '';
        
        if($length is int) {
            $currentLength = \strlen($this->buffer);

            if ($length >= $currentLength) {
                // No need to slice the buffer because we don't have enough data.
                $result = $this->buffer;
                $this->buffer = '';
            } else {
                // Slice up the result to provide a subset of the buffer.
                $result = Str\slice($this->buffer, 0, $length);
                $this->buffer = Str\slice($this->buffer, $length);
            }
        } else {
            $result = $this->buffer;
            $this->buffer = '';
        }

        return $result;
    }

    /**
     * Writes data to the buffer.
     */
    public function write(string $string): int
    {
        $this->buffer .= $string;

        if (\strlen($this->buffer) >= $this->hwm) {
            return 0;
        }

        return \strlen($string);
    }

    /**
     * {@inheritdoc}
     *
     * @return mixed
     */
    public function getMetadata(?string $key = null): mixed
    {
        if ($key === 'hwm') {
            return $this->hwm;
        }

        return $key ? null : dict[];
    }
}
