with Ada.Containers;
with Ada.Directories;
with Ada.Exceptions;
with Ada.Finalization;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Ada.Unchecked_Conversion;
with Interfaces.C;
with Interfaces.C.Strings;
with System;
with System.Storage_Elements;

with Meddb.Types;

package body Meddb.Wfdb is

   use Ada.Strings.Unbounded;
   use Interfaces.C;
   use Interfaces.C.Strings;

   type Siginfo is record
      Fname    : chars_ptr;
      Desc     : chars_ptr;
      Units    : chars_ptr;
      Gain     : double;
      Initval  : int;
      Group    : unsigned;
      Fmt      : int;
      Spf      : int;
      Bsize    : int;
      Adcres   : int;
      Adczero  : int;
      Baseline : int;
      Nsamp    : long;
      Cksum    : int;
   end record
   with Convention => C;

   type Sig_Array is array (0 .. 63) of Siginfo
   with Convention => C;

   type Anninfo is record
      Name : chars_ptr;
      Stat : int;
   end record
   with Convention => C;

   type C_Annotation is record
      Time   : long_long;
      Anntyp : char;
      Subtyp : signed_char;
      Chan   : unsigned_char;
      Num    : signed_char;
      Aux    : System.Address;
   end record
   with Convention => C;

   type Sample_Array is array (Natural range <>) of int
   with Convention => C;

   function Isigopen (Rec : chars_ptr; Si : System.Address; Nsig : int) return int
   with Import => True, Convention => C, External_Name => "isigopen";

   function Getvec (Vec : System.Address) return int
   with Import => True, Convention => C, External_Name => "getvec";

   function Annopen (Rec : chars_ptr; Ai : System.Address; Nann : unsigned) return int
   with Import => True, Convention => C, External_Name => "annopen";

   function Getann (A : unsigned; Ann : System.Address) return int
   with Import => True, Convention => C, External_Name => "wfdb_getann_LL";

   function Isigsettime (T : long_long) return int
   with Import => True, Convention => C, External_Name => "wfdb_isigsettime_LL";

   function Sampfreq (Rec : chars_ptr) return double
   with Import => True, Convention => C, External_Name => "sampfreq";

   function Aduphys (S : unsigned; Sample : int) return double
   with Import => True, Convention => C, External_Name => "aduphys";

   function Annstr (Code : int) return chars_ptr
   with Import => True, Convention => C, External_Name => "annstr";

   function Anndesc (Code : int) return chars_ptr
   with Import => True, Convention => C, External_Name => "anndesc";

   function Getinfo (Rec : chars_ptr) return chars_ptr
   with Import => True, Convention => C, External_Name => "getinfo";

   function Timstr (T : long_long) return chars_ptr
   with Import => True, Convention => C, External_Name => "wfdb_timstr_LL";

   procedure Wfdbquit
   with Import => True, Convention => C, External_Name => "wfdbquit";

   procedure Setwfdb (Path : chars_ptr)
   with Import => True, Convention => C, External_Name => "setwfdb";

   procedure Wfdbquiet
   with Import => True, Convention => C, External_Name => "wfdbquiet";

   type Session is new Ada.Finalization.Limited_Controlled with record
      Active : Boolean := False;
   end record;

   overriding procedure Finalize (Item : in out Session);

   overriding procedure Finalize (Item : in out Session) is
   begin
      if Item.Active then
         Wfdbquit;
         Item.Active := False;
      end if;
   end Finalize;

   function Clean (S : String) return String is
      Last : Integer := S'Last;
   begin
      while Last >= S'First
        and then (S (Last) = ASCII.NUL or else Character'Pos (S (Last)) < 32)
      loop
         Last := Last - 1;
      end loop;
      if Last < S'First then
         return "";
      end if;
      return S (S'First .. Last);
   end Clean;

   function Value_Or_Empty (P : chars_ptr) return String is
   begin
      if P = Null_Ptr then
         return "";
      end if;
      return Value (P);
   end Value_Or_Empty;

   function Aux_Text (Addr : System.Address) return String is
      use type System.Address;
      use System.Storage_Elements;
      type Byte is mod 256;
      type Byte_Ptr is access all Byte
      with Convention => C, Storage_Size => 0;
      function To_Ptr is new Ada.Unchecked_Conversion (System.Address, Byte_Ptr);
      Head : Byte_Ptr;
      Len  : Natural;
   begin
      if Addr = System.Null_Address then
         return "";
      end if;
      Head := To_Ptr (Addr);
      Len := Natural (Head.all);
      if Len = 0 then
         return "";
      end if;
      declare
         Result : String (1 .. Len);
      begin
         for I in 1 .. Len loop
            declare
               P : constant Byte_Ptr := To_Ptr (Addr + Storage_Offset (I));
            begin
               Result (I) := Character'Val (P.all);
            end;
         end loop;
         return Result;
      end;
   end Aux_Text;

   function Strip_Hea (Path : String) return String is
   begin
      if Path'Length > 4
        and then Ada.Strings.Fixed.Tail (Path, 4) = ".hea"
      then
         return Path (Path'First .. Path'Last - 4);
      end if;
      return Path;
   end Strip_Hea;

   procedure Read
     (Path      : String;
      Req       : Types.Read_Request;
      Annotator : String;
      Rec       : out Types.Recording)
   is
      Sess     : Session;
      Record_C : chars_ptr := Null_Ptr;
      Dir_C    : chars_ptr := Null_Ptr;
      Ann_Name : chars_ptr := Null_Ptr;
      Sigs     : Sig_Array;
      Info     : Anninfo;
      Nsig     : int;
      Fs       : Long_Float;
      Nsamp    : Long_Long_Integer := 0;
      Do_Load  : Boolean;
      Span     : Long_Float;
      Full     : constant String := Ada.Directories.Full_Name (Strip_Hea (Path));
      Base     : constant String := Ada.Directories.Simple_Name (Full);
      Dir      : constant String := Ada.Directories.Containing_Directory (Full);
   begin
      Rec := (others => <>);
      Wfdbquiet;
      Rec.Name := To_Unbounded_String (Base);
      Rec.Format_Name := To_Unbounded_String ("wfdb");
      Rec.Source := To_Unbounded_String (Path);
      Dir_C := New_String (if Dir'Length = 0 then "." else Dir);
      Setwfdb (Dir_C);
      Record_C := New_String (Base);
      Nsig := Isigopen (Record_C, Sigs'Address, Sigs'Length);
      if Nsig <= 0 then
         raise Meddb.Error with "cannot open WFDB record " & Path;
      end if;
      Sess.Active := True;
      Fs := Long_Float (Sampfreq (Null_Ptr));
      if Fs <= 0.0 then
         Fs := 1.0;
      end if;
      Rec.Start_Time := To_Unbounded_String (Value_Or_Empty (Timstr (0)));
      for S in 0 .. Integer (Nsig) - 1 loop
         declare
            Info_S : Siginfo renames Sigs (S);
            Ch     : Types.Channel;
            Count  : Long_Long_Integer := Long_Long_Integer (Info_S.Nsamp);
         begin
            if Info_S.Spf > 1 and then Count > 0 then
               Count := Count / Long_Long_Integer (Info_S.Spf);
            end if;
            if Count > Nsamp then
               Nsamp := Count;
            end if;
            Ch.Label := To_Unbounded_String
              (if Value_Or_Empty (Info_S.Desc)'Length > 0
               then Value_Or_Empty (Info_S.Desc)
               else "ch" & Types.Trim (Integer'Image (S + 1)));
            Ch.Units := To_Unbounded_String
              (if Value_Or_Empty (Info_S.Units)'Length > 0
               then Value_Or_Empty (Info_S.Units)
               elsif Long_Float (Info_S.Gain) /= 0.0 then "mV"
               else "adu");
            Ch.Sampling_Rate := Fs;
            Ch.Gain := Long_Float (Info_S.Gain);
            Ch.Baseline := Integer (Info_S.Baseline);
            Ch.Digital_Min := Integer (Info_S.Adczero);
            Ch.Samples_In_File := Count;
            Types.Add_Channel (Rec, Ch);
         end;
      end loop;
      if Nsamp > 0 then
         Rec.Duration := Long_Float (Nsamp) / Fs;
      end if;
      declare
         P : chars_ptr := Getinfo (Record_C);
         N : Natural := 0;
      begin
         while P /= Null_Ptr and then N < 100 loop
            Rec.Comments.Append (To_Unbounded_String (Value (P)));
            N := N + 1;
            P := Getinfo (Null_Ptr);
         end loop;
      end;

      Types.Decide_Load (Rec.Duration, Fs, Req, Do_Load, Span);
      Rec.Window_Start := Req.Start;
      Rec.Window_Duration := Span;

      Ann_Name := New_String (if Annotator'Length = 0 then "atr" else Annotator);
      Info := (Name => Ann_Name, Stat => 0);
      if Annopen (Record_C, Info'Address, 1) = 0 then
         declare
            Ann   : C_Annotation;
            Total : Natural := 0;
            Wend  : constant Long_Float := Req.Start + Span;
         begin
            while Getann (0, Ann'Address) = 0 loop
               declare
                  Onset : constant Long_Float :=
                    Long_Float (Ann.Time) / Fs;
                  Code  : constant int := int (char'Pos (Ann.Anntyp));
                  Label : constant String := Value_Or_Empty (Annstr (Code));
                  Desc  : constant String := Value_Or_Empty (Anndesc (Code));
                  Extra : constant String := Clean (Aux_Text (Ann.Aux));
                  Item  : Types.Annotation;
               begin
                  Total := Total + 1;
                  if Span > 0.0 and then Onset >= Req.Start and then Onset < Wend then
                     Item.Onset := Onset;
                     Item.Label := To_Unbounded_String (Label);
                     Item.Description := To_Unbounded_String
                       (if Extra'Length = 0 then Desc else Desc & " " & Extra);
                     Item.Channel := To_Unbounded_String
                       (Types.Trim (Integer'Image (Integer (Ann.Chan))));
                     Rec.Annotations.Append (Item);
                  end if;
               end;
            end loop;
            Rec.Annotations_In_File := Total;
         end;
      end if;

      if Do_Load then
         declare
            Origin : constant Long_Long_Integer :=
              Types.Start_Index (Fs, Req.Start);
            Count : constant Long_Long_Integer :=
              Types.Sample_Count (Fs, Span, Nsamp, Req.Start);
            Vec : Sample_Array (0 .. Integer (Nsig) - 1);
            Cols : array (0 .. Integer (Nsig) - 1) of Types.Sample_Vectors.Vector;
         begin
            for C of Cols loop
               C.Reserve_Capacity (Ada.Containers.Count_Type (Count));
            end loop;
            if Isigsettime (long_long (Origin)) /= 0 and then Origin /= 0 then
               raise Meddb.Error with "cannot seek in WFDB record " & Path;
            end if;
            for I in 1 .. Count loop
               pragma Unreferenced (I);
               exit when Getvec (Vec'Address) <= 0;
               for S in Vec'Range loop
                  Cols (S).Append (Long_Float (Aduphys (unsigned (S), Vec (S))));
               end loop;
            end loop;
            for S in Cols'Range loop
               Types.Set_Samples (Rec, S + 1, Cols (S));
            end loop;
         end;
      end if;
      if Sess.Active then
         null;
      end if;
      Free (Record_C);
      Free (Dir_C);
      Free (Ann_Name);
   exception
      when Meddb.Error =>
         Free (Record_C);
         Free (Dir_C);
         Free (Ann_Name);
         raise;
      when E : others =>
         Free (Record_C);
         Free (Dir_C);
         Free (Ann_Name);
         raise Meddb.Error with "WFDB read failed: " &
           Ada.Exceptions.Exception_Message (E);
   end Read;

end Meddb.Wfdb;
