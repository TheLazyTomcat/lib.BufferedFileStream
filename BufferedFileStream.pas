{-------------------------------------------------------------------------------

  This Source Code Form is subject to the terms of the Mozilla Public
  License, v. 2.0. If a copy of the MPL was not distributed with this
  file, You can obtain one at http://mozilla.org/MPL/2.0/.

-------------------------------------------------------------------------------}
{===============================================================================

  Buffered file stream

    Provides a TFileStream descendant TBufferedFileStream that is buffering
    all I/O operations (read/write) and also stream position and stream size
    (effectively buffering Seek operations).

    It was primarily developed for situation, where a large number of very
    small buffers (often single bytes) are being read or written - this would
    be extremely slow thanks to overhead of each such operation.
    But it can also be used in all other scenarios, as it is prepared for full
    random access (but in that case the buffering does not bring any benefit,
    and may even slow the operations down).

      WARNING - given the implementation, the stream cannot be created with
                limited file open mode (fmOpenRead or fmOpenWrite). Trying to
                do so will raise an EBFSInvalidValue exception in the
                constructor.

  Version 1.1.1 (2024-04-14)

  Last change 2024-04-14

  ©2023-2024 František Milt

  Contacts:
    František Milt: frantisek.milt@gmail.com

  Support:
    If you find this code useful, please consider supporting its author(s) by
    making a small donation using the following link(s):

      https://www.paypal.me/FMilt

  Changelog:
    For detailed changelog and history please refer to this git repository:

      github.com/TheLazyTomcat/Lib.BufferedFileStream

  Dependencies:
  * AuxExceptions - github.com/TheLazyTomcat/Lib.AuxExceptions
    AuxTypes      - github.com/TheLazyTomcat/Lib.AuxTypes

  Library AuxExceptions is required only when rebasing local exception classes
  (see symbol BufferedFileStream_UseAuxExceptions for details).

  Indirect dependencies:
    SimpleCPUID - github.com/TheLazyTomcat/Lib.SimpleCPUID
    StrRect     - github.com/TheLazyTomcat/Lib.StrRect
    UInt64Utils - github.com/TheLazyTomcat/Lib.UInt64Utils
    WinFileInfo - github.com/TheLazyTomcat/Lib.WinFileInfo

===============================================================================}
unit BufferedFileStream;
{
  BufferedFileStream_UseAuxExceptions

  If you want library-specific exceptions to be based on more advanced classes
  provided by AuxExceptions library instead of basic Exception class, and don't
  want to or cannot change code in this unit, you can define global symbol
  BufferedFileStream_UseAuxExceptions to achieve this.
}
{$IF Defined(BufferedFileStream_UseAuxExceptions)}
  {$DEFINE UseAuxExceptions}
{$IFEND}

//------------------------------------------------------------------------------

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$MODESWITCH DuplicateLocals+}
  {$DEFINE FPC_DisableWarns}
  {$MACRO ON}
{$ENDIF}
{$H+}

{$IFOPT Q+}
  {$DEFINE OverflowChecks}
{$ENDIF}

interface

uses
  SysUtils, Classes,
  AuxTypes{$IFDEF UseAuxExceptions}, AuxExceptions{$ENDIF};

{===============================================================================
    Library-specific exception
===============================================================================}
type
  EBFSException = class({$IFDEF UseAuxExceptions}EAEGeneralException{$ELSE}Exception{$ENDIF});

  //EBFSSyncError        = class(EBFSException);
  EBFSFlushError       = class(EBFSException);
  //EBFSSeekError        = class(EBFSException);
  //EBFSReadError        = class(EBFSException);
  //EBFSWriteError       = class(EBFSException);
  EBFSInvalidValue     = class(EBFSException);
  //EBFSInvalidOperation = class(EBFSException);

{===============================================================================
--------------------------------------------------------------------------------
                               TBufferedFileStream
--------------------------------------------------------------------------------
===============================================================================}
const
  BFS_BUFFER_SIZE_DEFAULT = 1024 * 1024;  // 1MiB

type
  // only for internal purposes, do bot use
  TBFSPositionType = set of (ptBuff,ptTrue);

{===============================================================================
    TBufferedFileStream - class declaration
===============================================================================}
type
  TBufferedFileStream = class(TFileStream)
  protected
    // buffer variables
    fBuffer:              Pointer;
    fBufferSize:          TMemSize;
    fBufferStart:         Int64;
    fBufferBytes:         Int64;
    fBufferChanged:       Boolean;
    // size and position buffering
    fTrueStreamSize:      Int64;
    fTrueStreamPosition:  Int64;
    fBuffStreamSize:      Int64;
    fBuffStreamPosition:  Int64;
    fBypassSeek:          Boolean;
    Function GetSize: Int64; override;
    procedure SetSize(const NewSize: Int64); override;
    procedure FlushBuffer; virtual;
    procedure FlushPosition; virtual;
    procedure SyncBuffer; virtual;
    procedure SyncPosition; virtual;
    procedure IncrementPosition(Which: TBFSPositionType; Delta: Int64); virtual;
    procedure Initialize(BufferSize: TMemSize); virtual;
    procedure Finalize; virtual;
    class Function CheckFileOpenMode(Mode: Word): Boolean; virtual;
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
  {
    Use auxiliary IO when you want to access some small distant data and then
    continue with standard buffered operation at original location.

    For example when writing data of unknown size and then storing their size
    in front of them - you first write some placeholder data where the size
    will be, then save the actual data using normal write that goes through
    buffering, seek to position of the size, do auxliliary write of the size
    and then seek back at the end of the data and continue next operation.

    Aux methods optimize such operations by not invalidating and flushing
    buffer when accesing data outside of it.
  }
    Function AuxiliaryRead(var Buffer; Count: LongInt): LongInt; virtual;
    Function AuxiliaryWrite(const Buffer; Count: LongInt): LongInt; virtual;
    procedure AuxiliaryReadBuffer(var Buffer; Count: LongInt); virtual;
    procedure AuxiliaryWriteBuffer(const Buffer; Count: LongInt); virtual;
    property BufferSize: TMemSize read fBufferSize;
  {$IFDEF Debug}
    property Buffer: Pointer read fBuffer;
    property BufferStart: Int64 read fBufferStart;   
    property BufferBytes: Int64 read fBufferBytes;
    property BufferChanged: Boolean read fBufferChanged;
    property TrueStreamSize: Int64 read fTrueStreamSize;
    property TrueStreamPosition: Int64 read fTrueStreamPosition;
    property BuffStreamSize: Int64 read fBuffStreamSize;
    property BuffStreamPosition: Int64 read fBuffStreamPosition;
  {$ENDIF}
  end;

{===============================================================================
--------------------------------------------------------------------------------
                            TBufferedWriteFileStream
--------------------------------------------------------------------------------
===============================================================================}
{===============================================================================
    TBufferedWriteFileStream - class declaration
===============================================================================}
type
  TBufferedWriteFileStream = class(TBufferedFileStream)
  protected
    procedure SyncBuffer; override;
    class Function CheckFileOpenMode(Mode: Word): Boolean; override;
  public
    Function Read(var Buffer; Count: LongInt): LongInt; override;
    Function AuxiliaryRead(var Buffer; Count: LongInt): LongInt; override;
  end;
(*
{===============================================================================
--------------------------------------------------------------------------------
                               TBufferedFileStream
--------------------------------------------------------------------------------
===============================================================================}
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
    fBypassSeek:          Boolean;
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
  {
    Use auxiliary IO when you want to access some small distant data and then
    continue with standard buffered operation at original location.

    For example when writing data of unknown size and then storing their size
    in front of them - you first write some placeholder data where the size
    will be, then save the actual data using normal write that goes through
    buffering, seek to position of the size, do auxliliary write of the size
    and then seek back at the end of the data and continue next operation.

    Aux methods optimize such operations by not invalidating and flushing
    buffer when accesing data outside of it.
  }
    Function AuxiliaryRead(var Buffer; Count: LongInt): LongInt; virtual;
    Function AuxiliaryWrite(const Buffer; Count: LongInt): LongInt; virtual;
    procedure AuxiliaryReadBuffer(var Buffer; Count: LongInt); virtual;
    procedure AuxiliaryWriteBuffer(const Buffer; Count: LongInt); virtual;
    property BufferSize: TMemSize read fBufferSize;
  end;
*)
implementation

uses
  Math;

{$IFDEF FPC_DisableWarns}
  {$DEFINE FPCDWM}
  {$DEFINE W4055:={$WARN 4055 OFF}} // Conversion between ordinals and pointers is not portable
{$ENDIF}

{===============================================================================
--------------------------------------------------------------------------------
                            TBufferedFileStream
--------------------------------------------------------------------------------
===============================================================================}
const
  BFS_BASICFILEACCESS_MASK = fmOpenRead or fmOpenWrite or fmOpenReadWrite;

//------------------------------------------------------------------------------

Function ConsumeArgs(const Args: array of const): Integer;
begin
Result := Length(Args);
end;  

//------------------------------------------------------------------------------

{$IFDEF OverflowChecks}{$Q-}{$ENDIF}
Function PtrAdvance(Ptr: Pointer; Offset: TMemOffset): Pointer;
var
  iPtr: PtrInt absolute Ptr;
  iRes: PtrInt absolute Result;
begin
iRes := iPtr + PtrInt(Offset);
end;
{$IFDEF OverflowChecks}{$Q+}{$ENDIF}

{===============================================================================
    TBufferedFileStream - class declaration
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
fBypassSeek := True;
try
  If NewSize <> fBuffStreamSize then
    begin
      If NewSize < (fBufferStart + fBufferBytes) then
        FlushBuffer;
      inherited SetSize(NewSize); // calls seek
      fTrueStreamSize := inherited Seek(0,soEnd);
      fTrueStreamPosition := inherited Seek(0,soCurrent);
      fBuffStreamSize := fTrueStreamSize;
      fBuffStreamPosition := fTrueStreamPosition;
    end;
finally
  fBypassSeek := False;
end;
end;

//------------------------------------------------------------------------------

procedure TBufferedFileStream.FlushBuffer;
begin
If fBufferBytes > 0 then
  begin
    If fBufferChanged then
      begin
        If fTrueStreamPosition <> fBufferStart then
          begin
            If inherited Seek(fBufferStart,soBeginning) <> fBufferStart then
              raise EBFSFlushError.CreateFmt('TBufferedFileStream.FlushBuffer: Cannot seek to buffer start (%d).',[fBufferStart]);
            fTrueStreamPosition := fBufferStart;
          end;
        // do not use WriteBuffer, raise exceptions locally
        If inherited Write(fBuffer^,LongInt(fBufferBytes)) <> fBufferBytes then
          raise EBFSFlushError.Create('TBufferedFileStream.FlushBuffer: Incomplete buffer flush.');
        IncrementPosition([ptTrue],fBufferBytes);
        // do not clear the buffer here, it will be cleared when needed
      end;
    fBufferStart := 0;
    fBufferBytes := 0;
    fBufferChanged := False;
  end;
end;

//------------------------------------------------------------------------------

procedure TBufferedFileStream.FlushPosition;
begin
If fBuffStreamPosition <> fTrueStreamPosition then
  begin
    If fBuffStreamPosition < 0 then
      fBuffStreamPosition := 0;
    If inherited Seek(fBuffStreamPosition,soBeginning) <> fBuffStreamPosition then
      raise EBFSFlushError.CreateFmt('TBufferedFileStream.FlushPosition: Cannot seek to buffered position (%d).',[fBuffStreamPosition]);
    fTrueStreamPosition := fBuffStreamPosition;
  end;
end;

//------------------------------------------------------------------------------

procedure TBufferedFileStream.SyncBuffer;
begin
{$message 'todo'}
fBufferStart := fBuffStreamPosition;
end;

//------------------------------------------------------------------------------

procedure TBufferedFileStream.SyncPosition;
begin
fTrueStreamPosition := inherited Seek(0,soCurrent);
fBuffStreamPosition := fTrueStreamPosition;
end;

//------------------------------------------------------------------------------

procedure TBufferedFileStream.IncrementPosition(Which: TBFSPositionType; Delta: Int64);
begin
If ptTrue in Which then
  begin
    Inc(fTrueStreamPosition,Delta);
    If fTrueStreamPosition > fTrueStreamSize then
      fTrueStreamSize := fTrueStreamPosition;
  end;
If ptBuff in Which then
  begin
    Inc(fBuffStreamPosition,Delta);
    If fBuffStreamPosition > fBuffStreamSize then
      fBuffStreamSize := fBuffStreamPosition;
  end;
end;

//------------------------------------------------------------------------------

procedure TBufferedFileStream.Initialize(BufferSize: TMemSize);
begin
// buffer size must be checked because of limitations (used types) in parent class
If BufferSize <= TMemSize(High(LongInt)) then
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
    fBypassSeek := False;
  end
else raise EBFSInvalidValue.CreateFmt('TBufferedFileStream.Initialize: Requested buffer size too large (%u).',[BufferSize]);
end;

//------------------------------------------------------------------------------

procedure TBufferedFileStream.Finalize;
begin
If Assigned(fBuffer) then
  begin
    FlushBuffer;
    FlushPosition;
    FreeMem(fBuffer,fBufferSize);
  end;
end;

//------------------------------------------------------------------------------

class Function TBufferedFileStream.CheckFileOpenMode(Mode: Word): Boolean;
begin
Result := ((Mode and fmCreate) = fmCreate) or ((Mode and BFS_BASICFILEACCESS_MASK) = fmOpenReadWrite);
end;

{-------------------------------------------------------------------------------
    TBufferedFileStream - public methods
-------------------------------------------------------------------------------}

constructor TBufferedFileStream.Create(BufferSize: TMemSize; const FileName: string; Mode: Word);
begin
If CheckFileOpenMode(Mode) then
  begin
    inherited Create(FileName,Mode);
    Initialize(BufferSize);
  end
else raise EBFSInvalidValue.CreateFmt('TBufferedFileStream.Create: Selected file open mode (%d) not allowed.',[Mode]);
end;

// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

constructor TBufferedFileStream.Create(BufferSize: TMemSize; const FileName: string; Mode: Word; Rights: Cardinal);
begin
If CheckFileOpenMode(Mode) then
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
If not fBypassSeek then
  begin
    case Origin of
      soCurrent:    Result := fBuffStreamPosition + Offset;
      soBeginning:  Result := Offset;
      soEnd:        Result := fBuffStreamSize + Offset;
    else
      raise EBFSInvalidValue.CreateFmt('TBufferedFileStream.Seek: Invalid seek origin (%d).',[Ord(Origin)]);
    end;
    // do no change buffered position for invalid (negative) offsets  
    If Result >= 0 then
      fBuffStreamPosition := Result
    else
      Result := -1;
  end
else Result := inherited Seek(Offset,Origin);
end;

//------------------------------------------------------------------------------

Function TBufferedFileStream.Read(var Buffer; Count: LongInt): LongInt;
begin
{$message 'todo'}
Result := 0;
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
      {
        Writing within the buffered bytes or directly behind them (we cannot
        allow data discontinuity, even if within the allocated buffer).
      }
        BufferPosition := fBuffStreamPosition - fBufferStart;
        If Count < LongInt(fBufferSize - BufferPosition) then
          begin
            // all data can fit into the buffer
            Move(Buffer,PtrAdvance(fBuffer,TMemOff(BufferPosition))^,Count);
            If fBufferBytes < (BufferPosition + Count) then
              fBufferBytes := BufferPosition + Count;
            fBufferChanged := True;
            IncrementPosition([ptBuff],Count);
            Result := Count;            
          end
        else
          begin
            // data will overflow the buffer, write what can fit now
            Result := fBufferSize - BufferPosition;
            If Result > 0 then
              begin
                Move(Buffer,PtrAdvance(fBuffer,TMemOff(BufferPosition))^,Result);
                fBufferChanged := True;
              end;
            fBufferBytes := Int64(fBufferSize);
            IncrementPosition([ptBuff],Result);
            FlushBuffer;
            Inc(Result,Write(PtrAdvance(@Buffer,TMemOff(Result))^,Count - Result)); 
          end;
      end
    else
      begin
        // writing outside the buffered data
        FlushBuffer;
        If Count < LongInt(fBufferSize) then
          begin
            // written data can fit into the buffer
            SyncBuffer;
            Move(Buffer,fBuffer^,Count);
            If fBufferBytes < Count then
              fBufferBytes := Count;
            fBufferChanged := True;
            IncrementPosition([ptBuff],Count);
            Result := Count;
          end
        else
          begin
          {
            Data cannot fit in the buffer (or they would fill it) - there is
            no point in buffering them, do direct write.
          }
            Result := inherited Write(Buffer,Count);
            IncrementPosition([ptBuff,ptTrue],Result);
          end;
      end;
  end
else Result := 0;
end;

//------------------------------------------------------------------------------

procedure TBufferedFileStream.Flush;
begin
FlushBuffer;
FlushPosition;
end;

//------------------------------------------------------------------------------

Function TBufferedFileStream.UnbufferedRead(var Buffer; Count: LongInt): LongInt;
begin
If Count > 0 then
  begin
    FlushBuffer;
    FlushPosition;
    Result := inherited Read(Buffer,Count);
    // note read should never lead to change in size
    IncrementPosition([ptBuff,ptTrue],Result);
  end
else Result := 0;
end;

//------------------------------------------------------------------------------

Function TBufferedFileStream.UnbufferedWrite(const Buffer; Count: LongInt): LongInt;
begin
If Count > 0 then
  begin
    FlushBuffer;
    FlushPosition;
    Result := inherited Write(Buffer,Count);
    IncrementPosition([ptBuff,ptTrue],Result);
  end
else Result := 0;
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

//------------------------------------------------------------------------------

Function TBufferedFileStream.AuxiliaryRead(var Buffer; Count: LongInt): LongInt;
begin
{$message 'todo'}
Result := 0;
end;

//------------------------------------------------------------------------------

Function TBufferedFileStream.AuxiliaryWrite(const Buffer; Count: LongInt): LongInt;
var
  BytesToWrite: LongInt;
  BytesWritten: LongInt;
  MovingPtr:    PByte;
begin
If Count > 0 then
  begin
    If (fBuffStreamPosition >= fBufferStart) and (fBuffStreamPosition <= (fBufferStart + fBufferBytes)) and
       ((fBuffStreamPosition + Count) <= (fBufferStart + Int64(fBufferSize))) then
      begin
        // entire write goes into the buffer
        Result := Write(Buffer,Count);
      end
    else If (fBuffStreamPosition >= (fBufferStart + Int64(fBufferSize))) or
            ((fBuffStreamPosition + Count) <= fBufferStart) then
      begin
      {
        Write goes completely outside of allocated buffer (not only buffered
        data). We can ignore buffer and write directly - even if we write into
        the buffer later, it cannot overwrite data stored here.
      }
        FlushPosition;
        Result := inherited Write(Buffer,Count);
        IncrementPosition([ptBuff,ptTrue],Result);
      end
    else If fBuffStreamPosition > (fBufferStart + fBufferBytes) then
      begin
      {
        Write at least partially overlaps allocated buffer, but does not form
        contiguous block with existing data. If we write directly, there is a
        risk the data will be overwritten by later buffering, therefore we need
        to flush buffer and run the write through buffered writing.
      }
        FlushBuffer;
        Result := Write(Buffer,Count);
      end
    else
      begin
      {
        Write partially overlaps the buffered data - it can start before or
        within them and can end pretty much anywhere.
      }
        Result := 0;
        MovingPtr := @Buffer;
        // directly write in front of the buffer
        If fBuffStreamPosition < fBufferStart then
          begin
            FlushPosition;
            // if write starts before buffer but overlaps it, it must end within it
            BytesToWrite := fBufferStart - fBuffStreamPosition;
            If inherited Write(MovingPtr^,BytesToWrite) <> BytesToWrite then
              raise EReadError.Create('TBufferedFileStream.AuxiliaryWrite: Failed to write data.');
            IncrementPosition([ptBuff,ptTrue],BytesToWrite);
            Dec(Count,BytesToWrite);
            Inc(MovingPtr,BytesToWrite);
            Inc(Result,BytesToWrite);
          end;
        // write into the buffer
        BytesToWrite := LongInt(Min(Int64(Count),(fBufferStart + Int64(fBufferSize)) - fBuffStreamPosition));
        BytesWritten := Write(MovingPtr^,BytesToWrite);
        // previous Write moved the positions as needed, do not do it again
        Dec(Count,BytesWritten);
        Inc(MovingPtr,BytesWritten);
        Inc(Result,BytesWritten);
        // write what is left behind the buffer
        If Count > 0 then
          begin
            FlushPosition;
            BytesWritten := inherited Write(MovingPtr^,Count);
            IncrementPosition([ptBuff,ptTrue],BytesWritten);
            Inc(Result,BytesWritten);
          end;
      end;
  end
else Result := 0;
end;

//------------------------------------------------------------------------------

procedure TBufferedFileStream.AuxiliaryReadBuffer(var Buffer; Count: LongInt);
begin
If AuxiliaryRead(Buffer,Count) <> Count then
  raise EReadError.Create('TBufferedFileStream.AuxiliaryReadBuffer: Read result does not match count.');
end;

//------------------------------------------------------------------------------

procedure TBufferedFileStream.AuxiliaryWriteBuffer(const Buffer; Count: LongInt);
begin
If AuxiliaryWrite(Buffer,Count) <> Count then
  raise EWriteError.Create('TBufferedFileStream.AuxiliaryWriteBuffer: Write result does not match count.');
end;


{===============================================================================
--------------------------------------------------------------------------------
                            TBufferedWriteFileStream
--------------------------------------------------------------------------------
===============================================================================}
{===============================================================================
    TBufferedWriteFileStream - class implementation
===============================================================================}
{-------------------------------------------------------------------------------
    TBufferedWriteFileStream - protected methods
-------------------------------------------------------------------------------}

procedure TBufferedWriteFileStream.SyncBuffer;
begin
fBufferStart := fBuffStreamPosition;
end;

//------------------------------------------------------------------------------

class Function TBufferedWriteFileStream.CheckFileOpenMode(Mode: Word): Boolean;
begin
Result := ((Mode and fmCreate) = fmCreate) or ((Mode and BFS_BASICFILEACCESS_MASK) in [fmOpenWrite,fmOpenReadWrite]);
end;

{-------------------------------------------------------------------------------
    TBufferedWriteFileStream - public methods
-------------------------------------------------------------------------------}

Function TBufferedWriteFileStream.Read(var Buffer; Count: LongInt): LongInt;
begin
ConsumeArgs([@Buffer,Count]);
Result := 0;
end;

//------------------------------------------------------------------------------

Function TBufferedWriteFileStream.AuxiliaryRead(var Buffer; Count: LongInt): LongInt;
begin
Result := UnbufferedRead(Buffer,Count);
end;


(*
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
fBypassSeek := True;
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
  fBypassSeek := False;
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
    fBypassSeek := False;
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
If (Mode = fmCreate) or ((Mode and 3) >= fmOpenReadWrite) then
  begin
    inherited Create(FileName,Mode);
    Initialize(BufferSize);
  end
else raise EBFSInvalidValue.CreateFmt('TBufferedFileStream.Create: Selected file open mode (%d) not allowed.',[Mode]);
end;

// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

constructor TBufferedFileStream.Create(BufferSize: TMemSize; const FileName: String; Mode: Word; Rights: Cardinal);
begin
If (Mode = fmCreate) or ((Mode and 3) >= fmOpenReadWrite) then
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
If not fBypassSeek then
  begin
    case Origin of
      soCurrent:    Result := fBuffStreamPosition + Offset;
      soBeginning:  Result := Offset;
      soEnd:        Result := fBuffStreamSize + Offset;
    else
      raise EBFSInvalidValue.CreateFmt('TBufferedFileStream.Seek: Invalid seek origin (%d).',[Ord(Origin)]);
    end;
    If Result >= 0 then
      fBuffStreamPosition := Result
    else
      Result := -1;
  end
else Result := inherited Seek(Offset,Origin);
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
            {$IFDEF FPCDWM}{$PUSH}W4055{$ENDIF}
              Move(Pointer(PtrUInt(fBuffer) + PtrUInt(BufferPosition))^,Buffer,Result);
            {$IFDEF FPCDWM}{$POP}{$ENDIF}
            Inc(fBuffStreamPosition,Result);
            Flush(False);
            // read the rest recursively
          {$IFDEF FPCDWM}{$PUSH}W4055{$ENDIF}
            Result := Result + Read(Pointer(PtrUInt(Addr(Buffer)) + PtrUInt(Result))^,Count - Result);
          {$IFDEF FPCDWM}{$POP}{$ENDIF}
          end
        else
          begin
            // all read data can be obtained from the buffer
          {$IFDEF FPCDWM}{$PUSH}W4055{$ENDIF}
            Move(Pointer(PtrUInt(fBuffer) + PtrUInt(BufferPosition))^,Buffer,Count);
          {$IFDEF FPCDWM}{$POP}{$ENDIF}
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
          {$IFDEF FPCDWM}{$PUSH}W4055{$ENDIF}
            Move(Buffer,Pointer(PtrUInt(fBuffer) + PtrUInt(BufferPosition))^,Count);
          {$IFDEF FPCDWM}{$POP}{$ENDIF}
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
              {$IFDEF FPCDWM}{$PUSH}W4055{$ENDIF}
                Move(Buffer,Pointer(PtrUInt(fBuffer) + PtrUInt(BufferPosition))^,Result);
              {$IFDEF FPCDWM}{$POP}{$ENDIF}
                fBufferChanged := True;
              end;
            fBufferBytes := Int64(fBufferSize);
            Inc(fBuffStreamPosition,Result);
            If fBuffStreamPosition > fBuffStreamSize then
              fBuffStreamSize := fBuffStreamPosition;
            Flush(False);
          {$IFDEF FPCDWM}{$PUSH}W4055{$ENDIF}
            Result := Result + Write(Pointer(PtrUInt(Addr(Buffer)) + PtrUInt(Result))^,Count - Result);
          {$IFDEF FPCDWM}{$POP}{$ENDIF}
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
If Count > 0 then
  begin
    Flush(True);
    Result := inherited Read(Buffer,Count);
    Inc(fTrueStreamPosition,Result);
    Inc(fBuffStreamPosition,Result);
  end
else Result := 0;
end;

//------------------------------------------------------------------------------

Function TBufferedFileStream.UnbufferedWrite(const Buffer; Count: LongInt): LongInt;
begin
If Count > 0 then
  begin
    Flush(True);
    Result := inherited Write(Buffer,Count);
    Inc(fTrueStreamPosition,Result);
    If fTrueStreamPosition > fTrueStreamSize then
      fTrueStreamSize := fTrueStreamPosition;
    Inc(fBuffStreamPosition,Result);
    If fBuffStreamPosition > fBuffStreamSize then
      fBuffStreamSize := fBuffStreamPosition;
  end
else Result := 0;
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

//------------------------------------------------------------------------------

Function TBufferedFileStream.AuxiliaryRead(var Buffer; Count: LongInt): LongInt;
var
  BytesToRead:  LongInt;
  BytesRead:    LongInt;
  MovingPtr:    PByte;
begin
If Count > 0 then
  begin
    If (fBuffStreamPosition >= fBufferStart) and
       ((fBuffStreamPosition + Count) <= (fBufferStart + fBufferBytes)) then
      begin
        // entire read can be done from the buffer
        Result := Read(Buffer,Count);
      end
    else If ((fBuffStreamPosition + Count) <= fBufferStart) or
            (fBuffStreamPosition  >= (fBufferStart + fBufferBytes)) then
      begin
        // entire read is outside of the buffer
        fTrueStreamPosition := inherited Seek(fBuffStreamPosition,soBeginning);
        fBuffStreamPosition := fTrueStreamPosition;
        Result := inherited Read(Buffer,Count);
        Inc(fBuffStreamPosition,Result);
        Inc(fTrueStreamPosition,Result);
      end
    else
      begin
        // there is partial overlap with the buffer
        Result := 0;
        MovingPtr := @Buffer;
        // read bytes in front of buffer, if any
        If fBuffStreamPosition < fBufferStart then
          begin
            fTrueStreamPosition := inherited Seek(fBuffStreamPosition,soBeginning);
            fBuffStreamPosition := fTrueStreamPosition;
            BytesToRead := fBufferStart - fBuffStreamPosition;
            If inherited Read(MovingPtr^,BytesToRead) <> BytesToRead then
              raise EReadError.Create('TBufferedFileStream.AuxiliaryRead: Failed to read data.');
            Dec(Count,BytesToRead);
            Inc(fBuffStreamPosition,BytesToRead);
            Inc(fTrueStreamPosition,BytesToRead);
            Inc(MovingPtr,BytesToRead);
            Inc(Result,BytesToRead);
          end;
        // now read bytes from the buffer
        BytesToRead := Min(Count,fBufferBytes - (fBuffStreamPosition - fBufferStart));
        BytesRead := Read(MovingPtr^,BytesToRead);  // moves fBuffStreamPosition
        Dec(Count,BytesRead);
        Inc(MovingPtr,BytesRead);
        Inc(Result,BytesRead);
        // read bytes behind the buffer, if any
        If Count > 0 then
          begin
            fTrueStreamPosition := inherited Seek(fBuffStreamPosition,soBeginning);
            fBuffStreamPosition := fTrueStreamPosition;
            BytesRead := inherited Read(MovingPtr^,Count);
            Inc(fBuffStreamPosition,BytesRead);
            Inc(fTrueStreamPosition,BytesRead);
            Inc(Result,BytesRead);
          end;
      end;
  end
else Result := 0;
end;

//------------------------------------------------------------------------------

Function TBufferedFileStream.AuxiliaryWrite(const Buffer; Count: LongInt): LongInt;
var
  BytesToWrite: LongInt;
  BytesWritten: LongInt;
  MovingPtr:    PByte;
begin
If Count > 0 then
  begin
    If (fBuffStreamPosition >= fBufferStart) and (fBuffStreamPosition <= (fBufferStart + fBufferBytes)) and
       ((fBuffStreamPosition + Count) <= (fBufferStart + Int64(fBufferSize))) then
      begin
        // entire write goes into the buffer
        Result := Write(Buffer,Count);
      end
    else If ((fBuffStreamPosition + Count) <= fBufferStart) or
            (fBuffStreamPosition > (fBufferStart + fBufferBytes)) then
      begin
        // entire write is outside of the buffer
        fTrueStreamPosition := inherited Seek(fBuffStreamPosition,soBeginning);
        fBuffStreamPosition := fTrueStreamPosition;
        Result := inherited Write(Buffer,Count);
        Inc(fBuffStreamPosition,Result);
        Inc(fTrueStreamPosition,Result);
        // reload size, because it might have changed
        fTrueStreamSize := inherited Seek(0,soEnd);
        If fBuffStreamSize < fTrueStreamSize then
          fBuffStreamSize := fTrueStreamSize;
        fTrueStreamPosition := inherited Seek(fBuffStreamPosition,soBeginning);
        fBuffStreamPosition := fTrueStreamPosition;
      end
    else
      begin
        // partial overlap
        Result := 0;
        MovingPtr := @Buffer;
        // write in front of the buffer
        If fBuffStreamPosition < fBufferStart then
          begin
            fTrueStreamPosition := inherited Seek(fBuffStreamPosition,soBeginning);
            fBuffStreamPosition := fTrueStreamPosition;
            BytesToWrite := fBufferStart - fBuffStreamPosition;
            If inherited Write(MovingPtr^,BytesToWrite) <> BytesToWrite then
              raise EReadError.Create('TBufferedFileStream.AuxiliaryWrite: Failed to write data.');
            Dec(Count,BytesToWrite);
            Inc(fBuffStreamPosition,BytesToWrite);
            Inc(fTrueStreamPosition,BytesToWrite);
            Inc(MovingPtr,BytesToWrite);
            Inc(Result,BytesToWrite);
          end;
        // write into the buffer
        BytesToWrite := Min(Count,Int64(fBufferSize) - (fBuffStreamPosition - fBufferStart));
        BytesWritten := Write(MovingPtr^,BytesToWrite);
        Dec(Count,BytesWritten);
        Inc(MovingPtr,BytesWritten);
        Inc(Result,BytesWritten);
        // write behind the buffer
        If Count > 0 then
          begin
            fTrueStreamPosition := inherited Seek(fBuffStreamPosition,soBeginning);
            fBuffStreamPosition := fTrueStreamPosition;
            BytesWritten := inherited Write(MovingPtr^,Count);
            Inc(fBuffStreamPosition,BytesWritten);
            Inc(fTrueStreamPosition,BytesWritten);
            Inc(Result,BytesWritten);
          end;
        // reload size
        fTrueStreamSize := inherited Seek(0,soEnd);
        If fBuffStreamSize < fTrueStreamSize then
          fBuffStreamSize := fTrueStreamSize;
        If Count > 0 then
          begin
            fTrueStreamPosition := inherited Seek(fBuffStreamPosition,soBeginning);
            fBuffStreamPosition := fTrueStreamPosition;
          end
        else fTrueStreamPosition := inherited Seek(fTrueStreamPosition,soBeginning);
      end;
  end
else Result := 0;
end;

//------------------------------------------------------------------------------

procedure TBufferedFileStream.AuxiliaryReadBuffer(var Buffer; Count: LongInt);
begin
If AuxiliaryRead(Buffer,Count) <> Count then
  raise EReadError.Create('TBufferedFileStream.AuxiliaryReadBuffer: Read result does not match count.');
end;

//------------------------------------------------------------------------------

procedure TBufferedFileStream.AuxiliaryWriteBuffer(const Buffer; Count: LongInt);
begin
If AuxiliaryWrite(Buffer,Count) <> Count then
  raise EWriteError.Create('TBufferedFileStream.AuxiliaryWriteBuffer: Write result does not match count.');
end;
*)
end.
