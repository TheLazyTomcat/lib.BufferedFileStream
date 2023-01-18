unit BufferedFileStream;

interface

uses
  SysUtils, Classes,
  AuxTypes;

type
  EBFSException = class(Exception);

  EBFSInvalidValue = class(EBFSException);
  EBFSFlushError   = class(EBFSException);

{===============================================================================
--------------------------------------------------------------------------------
                               TBufferedFileStream
--------------------------------------------------------------------------------
===============================================================================}
const
  BFS_BUFFER_SIZE_DEFAULT = 1024 * 1024;  // 1MiB

{===============================================================================
    TBufferedFileStream - class declaration
===============================================================================}
type
  TBufferedFileStream = class(TFileStream)
  protected
    fBuffer:              Pointer;
    fBufferSize:          TMemSize;
    fBufferStart:         Int64;
    fBufferBytes:         Int64;
    fBufferChanged:       Boolean;
    fTrueStreamSize:      Int64;
    fTrueStreamPosition:  Int64;
    fBuffStreamSize:      Int64;
    fBuffStreamPosition:  Int64;
    fSettingSize:         Boolean;
    Function GetSize: Int64; override;
    procedure SetSize(const NewSize: Int64); override;
    procedure LoadBuffer; virtual;
    procedure Flush(FlushPosition: Boolean); overload; virtual;
    procedure Initialize(BufferSize: TMemSize); virtual;
    procedure Finalize; virtual;
  public
    constructor Create(BufferSize: TMemSize; const FileName: string; Mode: Word); overload;
    constructor Create(BufferSize: TMemSize; const FileName: string; Mode: Word; Rights: Cardinal); overload;
    constructor Create(const FileName: string; Mode: Word); overload;
    constructor Create(const FileName: string; Mode: Word; Rights: Cardinal); overload;
    destructor Destroy; override;
    Function Seek(const Offset: Int64; Origin: TSeekOrigin): Int64; override;
    Function Read(var Buffer; Count: LongInt): LongInt; override;
    Function Write(const Buffer; Count: LongInt): LongInt; override;
    procedure Flush; overload; virtual;
    // flush buffer and then do read/write directly via inherited methods
    Function UnbufferedRead(var Buffer; Count: LongInt): LongInt; virtual;
    Function UnbufferedWrite(const Buffer; Count: LongInt): LongInt; virtual;
    procedure UnbufferedReadBuffer(var Buffer; Count: LongInt); virtual;
    procedure UnbufferedWriteBuffer(const Buffer; Count: LongInt); virtual;
    property BufferSize: TMemSize read fBufferSize;
  end;

implementation

{===============================================================================
--------------------------------------------------------------------------------
                               TBufferedFileStream
--------------------------------------------------------------------------------
===============================================================================}
{===============================================================================
    TBufferedFileStream - class implementation
===============================================================================}
{-------------------------------------------------------------------------------
    TBufferedFileStream - protected methods
-------------------------------------------------------------------------------}

Function TBufferedFileStream.GetSize: Int64;
begin
Result := fBuffStreamSize;
end;

//------------------------------------------------------------------------------

procedure TBufferedFileStream.SetSize(const NewSize: Int64);
begin
fSettingSize := True;
try
  If NewSize <> fBuffStreamSize then
    begin
      If NewSize < (fBufferStart + fBufferBytes) then
        Flush(False);
      inherited SetSize(NewSize); // calls seek
      fTrueStreamSize := inherited Seek(0,soEnd);
      fTrueStreamPosition := inherited Seek(0,soCurrent);
      fBuffStreamSize := fTrueStreamSize;
      fBuffStreamPosition := fTrueStreamPosition;
    end;
finally
  fSettingSize := False;
end;
end;

//------------------------------------------------------------------------------

procedure TBufferedFileStream.LoadBuffer;
begin
If fTrueStreamPosition <> fBuffStreamPosition then
  begin
    fTrueStreamPosition := inherited Seek(fBuffStreamPosition,soBeginning);
    fBuffStreamPosition := fTrueStreamPosition;
  end;
fBufferStart := fBuffStreamPosition;
FillChar(fBuffer^,fBufferSize,0);
fBufferBytes := Int64(inherited Read(fBuffer^,LongInt(fBufferSize)));
fBufferChanged := False;
Inc(fTrueStreamPosition,fBufferBytes);
end;

//------------------------------------------------------------------------------

procedure TBufferedFileStream.Flush(FlushPosition: Boolean);
begin
If fBufferBytes > 0 then
  begin
    If fBufferChanged then
      begin
        If fTrueStreamPosition <> fBufferStart then
          fTrueStreamPosition := inherited Seek(fBufferStart,soBeginning);
        If inherited Write(fBuffer^,LongInt(fBufferBytes)) <> fBufferBytes then
          raise EBFSFlushError.Create('TBufferedFileStream.Flush: Buffer flush incomplete.');
        Inc(fTrueStreamPosition,fBufferBytes);
        If fTrueStreamPosition > fTrueStreamSize then
          fTrueStreamSize := fTrueStreamPosition;
      end;
    fBufferStart := 0;
    fBufferBytes := 0;
    fBufferChanged := False;
  end;
If FlushPosition then
  begin
    fTrueStreamPosition := inherited Seek(fBuffStreamPosition,soBeginning);
    fBuffStreamPosition := fTrueStreamPosition;
  end;
end;

//------------------------------------------------------------------------------

procedure TBufferedFileStream.Initialize(BufferSize: TMemSize);
begin
If BufferSize <= $40000000{1GiB} then
  begin
    // init fields
    fBuffer := AllocMem(BufferSize);
    fBufferSize := BufferSize;
    fBufferStart := 0;
    fBufferBytes := 0;
    fBufferChanged := False;
    fTrueStreamSize := inherited Seek(0,soEnd);
    fTrueStreamPosition := inherited Seek(0,soBeginning);
    fBuffStreamSize := fTrueStreamSize;
    fBuffStreamPosition := fTrueStreamPosition;
    fSettingSize := False;
  end
else raise EBFSInvalidValue.CreateFmt('TBufferedFileStream.Initialize: Requested buffer size too large (%u).',[BufferSize]);
end;

//------------------------------------------------------------------------------

procedure TBufferedFileStream.Finalize;
begin
If Assigned(fBuffer) then
  begin
    Flush;
    FreeMem(fBuffer,fBufferSize);
  end;
end;

{-------------------------------------------------------------------------------
    TBufferedFileStream - public methods
-------------------------------------------------------------------------------}

constructor TBufferedFileStream.Create(BufferSize: TMemSize; const FileName: String; Mode: Word);
begin
If not((Mode and 3) in [fmOpenWrite,fmOpenRead]) then
  begin
    inherited Create(FileName,Mode);
    Initialize(BufferSize);
  end
else raise EBFSInvalidValue.CreateFmt('TBufferedFileStream.Create: Selected file open mode (%d) not allowed.',[Mode]);
end;

// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

constructor TBufferedFileStream.Create(BufferSize: TMemSize; const FileName: String; Mode: Word; Rights: Cardinal);
begin
If not((Mode and 3) in [fmOpenWrite,fmOpenRead]) then
  begin
    inherited Create(FileName,Mode,Rights);
    Initialize(BufferSize);
  end
else raise EBFSInvalidValue.CreateFmt('TBufferedFileStream.Create: Selected file open mode (%d) not allowed.',[Mode]);
end;

// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

constructor TBufferedFileStream.Create(const FileName: string; Mode: Word);
begin
Create(BFS_BUFFER_SIZE_DEFAULT,FileName,Mode);
end;

// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

constructor TBufferedFileStream.Create(const FileName: string; Mode: Word; Rights: Cardinal);
begin
Create(BFS_BUFFER_SIZE_DEFAULT,FileName,Mode,Rights);
end;

//------------------------------------------------------------------------------

destructor TBufferedFileStream.Destroy;
begin
Finalize;
inherited;
end;

//------------------------------------------------------------------------------

Function TBufferedFileStream.Seek(const Offset: Int64; Origin: TSeekOrigin): Int64;
begin
If not fSettingSize then
  begin
    case Origin of
      soCurrent:    Result := fBuffStreamPosition + Offset;
      soBeginning:  Result := Offset;
      soEnd:        Result := fBuffStreamSize + Offset;
    else
      raise EBFSInvalidValue.CreateFmt('TBufferedFileStream.Seek: Invalid seek origin (%d).',[Ord(Origin)]);
    end;
    fBuffStreamPosition := Result;
  end
else Result := Inherited Seek(Offset,Origin);
end;

//------------------------------------------------------------------------------

Function TBufferedFileStream.Read(var Buffer; Count: LongInt): LongInt;
var
  BufferPosition: Int64;
begin
If Count > 0 then
  begin
    If (fBuffStreamPosition >= fBufferStart) and (fBuffStreamPosition < (fBufferStart + fBufferBytes)) then
      begin
        // reading from the buffer
        BufferPosition := fBuffStreamPosition - fBufferStart;
        If Count > LongInt(fBufferBytes - BufferPosition) then
          begin
            // not all requested data are in the buffer
            Result := fBufferBytes - BufferPosition;
            If Result > 0 then
              Move(Pointer(PtrUInt(fBuffer) + PtrUInt(BufferPosition))^,Buffer,Result);
            Inc(fBuffStreamPosition,Result);
            Flush(False);
            // read the rest recursively
            Result := Result + Read(Pointer(PtrUInt(Addr(Buffer)) + PtrUInt(Result))^,Count - Result);            
          end
        else
          begin
            // all read data can be obtained from the buffer
            Move(Pointer(PtrUInt(fBuffer) + PtrUInt(BufferPosition))^,Buffer,Count);
            Inc(fBuffStreamPosition,Count);
            Result := Count;
          end;
      end
    else
      begin
        // reading from a position outside of the buffer
        Flush(False);
        If Count < LongInt(fBufferSize) then
          begin
            // read data can fit inside the buffer
            LoadBuffer;
            If fBufferBytes < Count then
              Result := fBufferBytes
            else
              Result := Count;
            If Result > 0 then
              begin
                Move(fBuffer^,Buffer,Result);
                Inc(fBuffStreamPosition,Result);
              end;
          end
        else
          begin
            // read data cannot fit into the buffer (or are of equal size), do direct read
            If fTrueStreamPosition <> fBuffStreamPosition then
              fTrueStreamPosition := inherited Seek(fBuffStreamPosition,soBeginning);
            fBuffStreamPosition := fTrueStreamPosition;
            Result := inherited Read(Buffer,Count);
            Inc(fTrueStreamPosition,Result);
            Inc(fBuffStreamPosition,Result);
          end;
      end;
  end
else Result := 0;
end;

//------------------------------------------------------------------------------

Function TBufferedFileStream.Write(const Buffer; Count: LongInt): LongInt;
var
  BufferPosition: Int64;
begin
If Count > 0 then
  begin
    If (fBuffStreamPosition >= fBufferStart) and (fBuffStreamPosition <= (fBufferStart + fBufferBytes)) then
      begin
        // writing inside the buffer
        BufferPosition := fBuffStreamPosition - fBufferStart;
        If Count < LongInt(fBufferSize - BufferPosition) then
          begin
            // written data can fit into the buffer
            Move(Buffer,Pointer(PtrUInt(fBuffer) + PtrUInt(BufferPosition))^,Count);
            If fBufferBytes < (BufferPosition + Count) then
              fBufferBytes := BufferPosition + Count;
            fBufferChanged := True;
            Inc(fBuffStreamPosition,Count);
            If fBuffStreamPosition > fBuffStreamSize then
              fBuffStreamSize := fBuffStreamPosition;
            Result := Count;
          end
        else
          begin
            // data will overflow the buffer, write what can fit now
            Result := fBufferSize - BufferPosition;
            If Result > 0 then
              begin
                Move(Buffer,Pointer(PtrUInt(fBuffer) + PtrUInt(BufferPosition))^,Result);
                fBufferChanged := True;
              end;
            fBufferBytes := fBufferSize;
            Inc(fBuffStreamPosition,Result);
            If fBuffStreamPosition > fBuffStreamSize then
              fBuffStreamSize := fBuffStreamPosition;
            Flush(False);
            Result := Result + Write(Pointer(PtrUInt(Addr(Buffer)) + PtrUInt(Result))^,Count - Result);
          end;
      end
    else
      begin
        // writing outside the buffer
        Flush(False);
        If Count < LongInt(fBufferSize) then
          begin
            // written data can fit into the buffer
            LoadBuffer;
            Move(Buffer,fBuffer^,Count);
            If fBufferBytes < Count then
              fBufferBytes := Count;
            fBufferChanged := True;
            Inc(fBuffStreamPosition,Count);
            If fBuffStreamPosition > fBuffStreamSize then
              fBuffStreamSize := fBuffStreamPosition;
            Result := Count;
          end
        else
          begin
            // data being written are larger than the buffer (or of equal size), write them directly
            If fTrueStreamPosition <> fBuffStreamPosition then
              fTrueStreamPosition := inherited Seek(fBuffStreamPosition,soBeginning);
            fBuffStreamPosition := fTrueStreamPosition;
            Result := inherited Write(Buffer,Count);
            Inc(fTrueStreamPosition,Result);
            If fTrueStreamPosition > fTrueStreamSize then
              fTrueStreamSize := fTrueStreamPosition;
            Inc(fBuffStreamPosition,Result);
            If fBuffStreamPosition > fBuffStreamSize then
              fBuffStreamSize := fBuffStreamPosition;
          end
      end;
  end
else Result := 0;
end;

//------------------------------------------------------------------------------

procedure TBufferedFileStream.Flush;
begin
Flush(True);
end;

//------------------------------------------------------------------------------

Function TBufferedFileStream.UnbufferedRead(var Buffer; Count: LongInt): LongInt;
begin
Flush(True);
Result := inherited Read(Buffer,Count);
Inc(fTrueStreamPosition,Result);
Inc(fBuffStreamPosition,Result);
end;

//------------------------------------------------------------------------------

Function TBufferedFileStream.UnbufferedWrite(const Buffer; Count: LongInt): LongInt;
begin
Flush(True);
Result := inherited Write(Buffer,Count);
Inc(fTrueStreamPosition,Result);
If fTrueStreamPosition > fTrueStreamSize then
  fTrueStreamSize := fTrueStreamPosition;
Inc(fBuffStreamPosition,Result);
If fBuffStreamPosition > fBuffStreamSize then
  fBuffStreamSize := fBuffStreamPosition;
end;

//------------------------------------------------------------------------------

procedure TBufferedFileStream.UnbufferedReadBuffer(var Buffer; Count: LongInt);
begin
If UnbufferedRead(Buffer,Count) <> Count then
  raise EReadError.Create('TBufferedFileStream.UnbufferedReadBuffer: Read result does not match count.');
end;

//------------------------------------------------------------------------------

procedure TBufferedFileStream.UnbufferedWriteBuffer(const Buffer; Count: LongInt);
begin
If UnbufferedWrite(Buffer,Count) <> Count then
  raise EWriteError.Create('TBufferedFileStream.UnbufferedWriteBuffer: Write result does not match count.');
end;

end.
