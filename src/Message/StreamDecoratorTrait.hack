namespace HackHttp\Message;

/**
 * Stream decorator trait
 *
 * @property StreamInterface $stream
 */
trait StreamDecoratorTrait
{
    /** @var StreamInterface */
    private ?StreamInterface $stream;

    /**
     * @param StreamInterface $stream Stream to decorate
     */
    public function __construct(?StreamInterface $stream=null)
    {
        $this->stream = $stream;
    }

    public function __toString(): string
    {
        if ($this->isSeekable()) {
            $this->seek(0);
        }
        return $this->getContents();
       
    }

    public function getContents(): string
    {
        return ($this is StreamInterface ? Utils::copyToString($this): '');
    }

    public function close(): void
    {
        if($this->stream is nonnull) {
            $this->stream->close();
        }
    }

    /**
     * {@inheritdoc}
     *
     * @return mixed
     */
    public function getMetadata(?string $key = null): mixed
    {
        if($this->stream is null) {
            $this->stream = $this->createStream();
        }

        return ($this->stream is nonnull ? $this->stream->getMetadata($key): null);
    }

    public function detach(): void
    {
        if($this->stream is nonnull) {
            $this->stream->detach();
        }
    }

    public function getSize(): ?int
    {
        if($this->stream is null) {
            $this->stream = $this->createStream();
        }

        return ($this->stream is nonnull ? $this->stream->getSize(): null);
    }

    public function eof(): bool
    {
        if($this->stream is null) {
            $this->stream = $this->createStream();
        }

        return $this->stream is nonnull ? $this->stream->eof(): true;
    }

    public function tell(): int
    {
        if($this->stream is null) {
            $this->stream = $this->createStream();
        }

        return $this->stream is nonnull ? $this->stream->tell(): -1;
    }

    public function isReadable(): bool
    {
        if($this->stream is null) {
            $this->stream = $this->createStream();
        }

        return $this->stream is nonnull?  $this->stream->isReadable(): false;
    }

    public function isWritable(): bool
    {
        if($this->stream is null) {
            $this->stream = $this->createStream();
        }

        return $this->stream is nonnull? $this->stream->isWritable(): false;
    }

    public function isSeekable(): bool
    {
        if($this->stream is null) {
            $this->stream = $this->createStream();
        }

        return $this->stream is nonnull ? $this->stream->isSeekable(): false;
    }

    public function rewind(): void
    {
        if($this->stream is null) {
            $this->stream = $this->createStream();
        }

        if($this->stream is nonnull) {
            $this->seek(0);
        }
    }

    public function seek(int $offset, int $whence = \SEEK_SET): void
    {
        if($this->stream is null) {
            $this->stream = $this->createStream();
        }

        if($this->stream is nonnull) {
            $this->stream->seek($offset, $whence);
        }
    }

    public function read(?int $length): string
    {
        if($this->stream is null) {
            $this->stream = $this->createStream();
        }

        if($this->stream is nonnull) {
            return $this->stream->read($length);
        } else {
            return '';
        }
    }

    public function write(string $string): int
    {
        if($this->stream is null) {
            $this->stream = $this->createStream();
        }
        
        if($this->stream is nonnull) {
            return $this->stream->write($string);
        } else {
            return 0;
        }
    }

    /**
     * Implement in subclasses to dynamically create streams when requested.
     *
     * @throws \BadMethodCallException
     */
    protected function createStream(): StreamInterface
    {
        throw new \BadMethodCallException('Not implemented');
    }
}
