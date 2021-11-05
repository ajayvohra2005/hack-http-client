namespace HackHttp\Message;

/**
 * Decorator used to return only a subset of a stream.
 */
final class LimitStream implements StreamInterface
{
    use StreamDecoratorTrait;

    /** @var int Offset to start reading from */
    private int $offset=0;

    /** @var int Limit the number of bytes that can be read */
    private int $limit=-1;

    /**
     * @param StreamInterface $stream Stream to wrap
     * @param int             $limit  Total number of bytes to allow to be read
     *                                from the stream. Pass -1 for no limit.
     * @param int             $offset Position to seek to before reading (only
     *                                works on seekable streams).
     */
    public function __construct(
        StreamInterface $stream,
        int $limit = -1,
        int $offset = 0
    ) {
        $this->stream = $stream;
        $this->limit = $limit;
        $this->__setOffset($offset);
    }

    public function eof(): bool
    {
        // Always return true if the underlying stream is EOF
        $_stream = $this->stream;

        if($_stream is nonnull) {
            if($_stream->eof()) {
                return true;
            }
           
            // No limit and the underlying stream is not at EOF
            if ($this->limit === -1) {
                return false;
            }

            return $_stream->tell() >= $this->offset + $this->limit;
        } else {
            return true;
        }
    }

    /**
     * Returns the size of the limited subset of data
     */
    public function getSize(): ?int
    {
        $_stream = $this->stream;

        if($_stream is nonnull) {
            $length = $_stream->getSize();
            if ($length is null) {
                return null;
            } elseif ($this->limit === -1) {
                return $length - $this->offset;
            } else {
                return \min($this->limit, $length - $this->offset);
            }
        } else {
            return null;
        }
    }

    /**
     * Allow for a bounded seek on the read limited stream
     */
    public function seek(int $offset, int $whence = \SEEK_SET): void
    {
         $_stream = $this->stream;

        if($_stream is nonnull) {

            if ($whence !== \SEEK_SET || $offset < 0) {
                throw new \RuntimeException("Cannot seek to offset {$offset} with whence {$whence} %s");
            }

            $offset += $this->offset;

            if ($this->limit !== -1) {
                if ($offset > $this->offset + $this->limit) {
                    $offset = $this->offset + $this->limit;
                }
            }

            $_stream->seek($offset);
        }
    }

    /**
     * Give a relative tell()
     */
    public function tell(): int
    {
        $_stream = $this->stream;
        return ( $_stream is nonnull ? $_stream->tell() - $this->offset: -1);
    }

    /**
     * Set the offset to start limiting from
     *
     * @param int $offset Offset to seek to and begin byte limiting from
     *
     * @throws \RuntimeException if the stream cannot be seeked.
     */
    public function setOffset(int $offset): void {
      $this->__setOffset($offset);
    }

    private function __setOffset(int $offset): void
    {
        $_stream = $this->stream;

        if($_stream is nonnull) {
            $current = $_stream->tell();

            if ($current !== $offset) {
                // If the stream cannot seek to the offset position, then read to it
                if ($_stream->isSeekable()) {
                    $_stream->seek($offset);
                } elseif ($current > $offset) {
                    throw new \RuntimeException("Could not seek to stream offset $offset");
                } else {
                    $_stream->read($offset - $current);
                }
            }

            $this->offset = $offset;
        }
    }

    /**
     * Set the limit of bytes that the decorator allows to be read from the
     * stream.
     *
     * @param int $limit Number of bytes to allow to be read from the stream.
     *                   Use -1 for no limit.
     */
    public function setLimit(int $limit): void
    {
        $this->limit = $limit;
    }

    public function read(?int $length): string
    {
        $_stream = $this->stream;
        if($_stream is nonnull) {
            if ($this->limit === -1) {
                return $_stream->read($length);
            }

            // Check if the current position is less than the total allowed
            // bytes + original offset
            $remaining = ($this->offset + $this->limit) - $_stream->tell();
            if ($remaining > 0) {
                // Only return the amount of requested data, ensuring that the byte
                // limit is not exceeded
                return $_stream->read(\min($remaining, $length));
            }
        }

        return '';
    }
}
