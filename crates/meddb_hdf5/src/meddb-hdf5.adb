with Ada.Characters.Handling;
with Ada.Containers;
with Ada.Directories;
with Ada.Finalization;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Ada.Unchecked_Conversion;
with Interfaces.C;
with Interfaces.C.Strings;
with System;
with System.Storage_Elements;

with Meddb.Types;

package body Meddb.Hdf5 is

   use Ada.Strings.Unbounded;
   use Interfaces.C;
   use Interfaces.C.Strings;

   type File_Ptr is new System.Address;
   type Char_512 is array (1 .. 512) of char
   with Convention => C;
   type Char_32 is array (1 .. 32) of char
   with Convention => C;
   type Dim_Array is array (1 .. 4) of Interfaces.Unsigned_64
   with Convention => C;

   type Node is record
      Path       : Char_512;
      Dtype      : Char_32;
      Rank       : int;
      Dims       : Dim_Array;
      N_Elements : Interfaces.Unsigned_64;
   end record
   with Convention => C;

   function C_Open (Path : chars_ptr; Out_File : access File_Ptr) return int
   with Import => True, Convention => C, External_Name => "meddb_h5_open";

   procedure C_Close (File : File_Ptr)
   with Import => True, Convention => C, External_Name => "meddb_h5_close";

   function C_Error return chars_ptr
   with Import => True, Convention => C, External_Name => "meddb_h5_last_error";

   function C_Ndatasets (File : File_Ptr) return int
   with Import => True, Convention => C, External_Name => "meddb_h5_ndatasets";

   function C_Dataset (File : File_Ptr; Index : int; Item : access Node) return int
   with Import => True, Convention => C, External_Name => "meddb_h5_dataset";

   function C_Exists (File : File_Ptr; Path : chars_ptr) return int
   with Import => True, Convention => C, External_Name => "meddb_h5_exists";

   function C_Text (File : File_Ptr; Path : chars_ptr; Buf : System.Address; Cap : int)
      return int
   with Import => True, Convention => C, External_Name => "meddb_h5_read_text";

   function C_Scalar (File : File_Ptr; Path : chars_ptr; Out_Value : access double)
      return int
   with Import => True, Convention => C, External_Name => "meddb_h5_read_scalar";

   function C_Wave
     (File : File_Ptr; Path : chars_ptr; Start, Count : unsigned_long;
      Data : access System.Address; Nchan, Nsamp : access unsigned_long) return int
   with Import => True, Convention => C, External_Name => "meddb_h5_read_waveform";

   procedure C_Free (Ptr : System.Address)
   with Import => True, Convention => C, External_Name => "meddb_h5_free";

   type Session is new Ada.Finalization.Limited_Controlled with record
      Handle : File_Ptr := File_Ptr (System.Null_Address);
   end record;

   overriding procedure Finalize (Item : in out Session);

   overriding procedure Finalize (Item : in out Session) is
   begin
      if Item.Handle /= File_Ptr (System.Null_Address) then
         C_Close (Item.Handle);
         Item.Handle := File_Ptr (System.Null_Address);
      end if;
   end Finalize;

   function S (P : chars_ptr) return String is
   begin
      if P = Null_Ptr then
         return "";
      end if;
      return Value (P);
   end S;

   function To_Ada (A : Char_512) return String is
      Last : Natural := 0;
   begin
      for I in A'Range loop
         exit when A (I) = char'Val (0);
         Last := I;
      end loop;
      if Last = 0 then
         return "";
      end if;
      declare
         Result : String (1 .. Last);
      begin
         for I in Result'Range loop
            Result (I) := Character'Val (char'Pos (A (I)));
         end loop;
         return Result;
      end;
   end To_Ada;

   function To_Ada (A : Char_32) return String is
      Last : Natural := 0;
   begin
      for I in A'Range loop
         exit when A (I) = char'Val (0);
         Last := I;
      end loop;
      if Last = 0 then
         return "";
      end if;
      declare
         Result : String (1 .. Last);
      begin
         for I in Result'Range loop
            Result (I) := Character'Val (char'Pos (A (I)));
         end loop;
         return Result;
      end;
   end To_Ada;

   function Elem (Base : System.Address; Index : Long_Long_Integer) return double is
      use System.Storage_Elements;
      type Elem_Ptr is access all double
      with Convention => C, Storage_Size => 0;
      function To_Ptr is new Ada.Unchecked_Conversion (System.Address, Elem_Ptr);
   begin
      return To_Ptr (Base + Storage_Offset (Index) * (double'Size / System.Storage_Unit)).all;
   end Elem;

   function Read_Text (File : File_Ptr; Path : String) return String is
      Name : chars_ptr := New_String (Path);
      Buf : array (1 .. 256) of char := (others => char'Val (0));
      Rc : int;
   begin
      Rc := C_Text (File, Name, Buf'Address, Buf'Length);
      Free (Name);
      if Rc /= 0 then
         return "";
      end if;
      declare
         Last : Natural := 0;
      begin
         for I in Buf'Range loop
            exit when Buf (I) = char'Val (0);
            Last := I;
         end loop;
         if Last = 0 then
            return "";
         end if;
         declare
            Result : String (1 .. Last);
         begin
            for I in Result'Range loop
               Result (I) := Character'Val (char'Pos (Buf (I)));
            end loop;
            return Ada.Strings.Fixed.Trim (Result, Ada.Strings.Both);
         end;
      end;
   end Read_Text;

   function Exists (File : File_Ptr; Path : String) return Boolean is
      Name : chars_ptr := New_String (Path);
      Rc : constant int := C_Exists (File, Name);
   begin
      Free (Name);
      return Rc /= 0;
   end Exists;

   function Ends_With (Value, Suffix : String) return Boolean is
   begin
      return Value'Length >= Suffix'Length
        and then Value (Value'Last - Suffix'Length + 1 .. Value'Last) = Suffix;
   end Ends_With;

   procedure Add_Wave_Channel
     (Rec   : in out Types.Recording;
      File  : File_Ptr;
      Path  : String;
      Label : String;
      Units : String;
      Rate  : Long_Float;
      N     : Long_Long_Integer;
      Req   : Types.Read_Request)
   is
      Ch : Types.Channel;
      Do_Load : Boolean;
      Span : Long_Float;
   begin
      Ch.Label := To_Unbounded_String (Label);
      Ch.Units := To_Unbounded_String (Units);
      Ch.Sampling_Rate := Rate;
      Ch.Samples_In_File := N;
      declare
         Signal_Duration : constant Long_Float :=
           (if Rate > 0.0 then Long_Float (N) / Rate else 0.0);
      begin
         Types.Decide_Load (Signal_Duration, Rate, Req, Do_Load, Span);
         if Signal_Duration > Rec.Duration then
            Rec.Duration := Signal_Duration;
         end if;
      end;
      Types.Add_Channel (Rec, Ch);
      if not Do_Load then
         if Rate > Types.Fast_Rate_Hz then
            declare
               Item : Types.Channel := Rec.Channels (Rec.Channels.Last_Index);
            begin
               Item.Note := To_Unbounded_String ("not loaded; pass --duration or --full");
               Rec.Channels.Replace_Element (Rec.Channels.Last_Index, Item);
            end;
         end if;
         return;
      end if;
      declare
         Name : chars_ptr := New_String (Path);
         Data : aliased System.Address := System.Null_Address;
         Nchan, Nsamp : aliased unsigned_long;
         Origin : constant unsigned_long :=
           unsigned_long (Types.Start_Index (Rate, Req.Start));
         Count : constant unsigned_long :=
           unsigned_long (Types.Sample_Count
             (Rate, Span, N, Req.Start));
         Rc : int;
      begin
         Rc := C_Wave (File, Name, Origin, Count, Data'Access, Nchan'Access, Nsamp'Access);
         Free (Name);
         if Rc /= 0 then
            raise Meddb.Error with "cannot read " & Path & ": " & S (C_Error);
         end if;
         declare
            Column : Types.Sample_Vectors.Vector;
            Samples : constant Long_Long_Integer := Long_Long_Integer (Nsamp);
         begin
            Column.Reserve_Capacity (Ada.Containers.Count_Type (Samples));
            for I in 0 .. Samples - 1 loop
               Column.Append (Long_Float (Elem (Data, I)));
            end loop;
            Types.Set_Samples (Rec, Positive (Rec.Channels.Last_Index), Column);
         end;
         C_Free (Data);
         if Span > Rec.Window_Duration then
            Rec.Window_Duration := Span;
         end if;
      end;
   end Add_Wave_Channel;

   procedure Load_Heartcycle
     (Rec  : in out Types.Recording;
      File : File_Ptr;
      Req  : Types.Read_Request)
   is
   begin
      for Node of Rec.Structure loop
         declare
            Path : constant String := To_String (Node.Path);
         begin
            if Ends_With (Path, "/data/value")
              and then Ada.Strings.Fixed.Index (Path, "/measure/value/") > 0
              and then Node.Rank <= 2
            then
               declare
                  Prefix : constant String :=
                    Path (Path'First .. Path'Last - String'("/data/value")'Length);
                  Label : constant String := Read_Text (File, Prefix & "/label/value");
                  Rate_Text : constant String := Read_Text (File, Prefix & "/Rate/value");
                  Unit : constant String := Read_Text (File, Prefix & "/Unit/value");
                  Rate : Long_Float := 0.0;
                  Upper : constant String :=
                    Ada.Characters.Handling.To_Upper
                      (if Label'Length = 0 then "signal" else Label);
               begin
                  begin
                     if Rate_Text'Length > 0 then
                        Rate := Long_Float'Value (Rate_Text);
                     end if;
                  exception
                     when Constraint_Error =>
                        Rate := 0.0;
                  end;
                  if Ada.Strings.Fixed.Index (Upper, "PEAK") > 0
                    and then Node.N_Elements < 5_000
                    and then Rate <= 1.0
                  then
                     declare
                        Name : chars_ptr := New_String (Path);
                        Data : aliased System.Address := System.Null_Address;
                        Nchan, Nsamp : aliased unsigned_long;
                        Rc : int;
                     begin
                        Rc := C_Wave
                          (File, Name, 0, unsigned_long (Node.N_Elements),
                           Data'Access, Nchan'Access, Nsamp'Access);
                        Free (Name);
                        if Rc = 0 then
                           for I in 0 .. Long_Long_Integer (Nsamp) - 1 loop
                              Rec.Annotations.Append
                                ((Onset => Long_Float (Elem (Data, I)),
                                  Duration => 0.0,
                                  Label => To_Unbounded_String (Label),
                                  Channel => Null_Unbounded_String,
                                  Description => To_Unbounded_String (Label)));
                           end loop;
                           Rec.Annotations_In_File :=
                             Rec.Annotations_In_File + Natural (Nsamp);
                           C_Free (Data);
                        end if;
                     end;
                  elsif Rate > 0.0
                    and then Node.N_Elements >= 32
                    and then Node.N_Elements < 5_000_000
                  then
                     Add_Wave_Channel
                       (Rec, File, Path,
                        (if Label'Length = 0 then Prefix else Label),
                        Unit, Rate, Node.N_Elements, Req);
                  end if;
               end;
            end if;
         end;
      end loop;
   end Load_Heartcycle;

   procedure Load_But
     (Rec  : in out Types.Recording;
      File : File_Ptr;
      Req  : Types.Read_Request)
   is
      Name : chars_ptr := New_String ("/sampling_freq");
      Fs_Raw : aliased double := 0.0;
      N : Long_Long_Integer := 0;
   begin
      if C_Scalar (File, Name, Fs_Raw'Access) /= 0 then
         Free (Name);
         raise Meddb.Error with "BUT CGM file has no /sampling_freq";
      end if;
      Free (Name);
      for Node of Rec.Structure loop
         if To_String (Node.Path) = "/ECG" then
            N := Node.N_Elements;
            exit;
         end if;
      end loop;
      Add_Wave_Channel
        (Rec, File, "/ECG", "ECG", "adu", Long_Float (Fs_Raw), N, Req);
      Rec.Comments.Append (To_Unbounded_String ("layout: BUT CGM"));
   end Load_But;

   procedure Read
     (Path : String;
      Req  : Types.Read_Request;
      Rec  : out Types.Recording)
   is
      Sess : Session;
      Name : chars_ptr := New_String (Path);
      Handle : aliased File_Ptr := File_Ptr (System.Null_Address);
      Heart : Boolean := False;
      But : Boolean := False;
   begin
      Rec := (others => <>);
      if C_Open (Name, Handle'Access) /= 0 then
         Free (Name);
         raise Meddb.Error with "cannot open " & Path & ": " & S (C_Error);
      end if;
      Free (Name);
      Sess.Handle := Handle;
      Rec.Name := To_Unbounded_String (Ada.Directories.Simple_Name (Path));
      Rec.Format_Name := To_Unbounded_String ("hdf5");
      Rec.Source := To_Unbounded_String (Path);
      for Index in 0 .. Integer (C_Ndatasets (Sess.Handle)) - 1 loop
         declare
            Item : aliased Node;
            Node_Rec : Types.Structure_Node;
         begin
            if C_Dataset (Sess.Handle, int (Index), Item'Access) = 0 then
               Node_Rec.Path := To_Unbounded_String (To_Ada (Item.Path));
               Node_Rec.Dtype := To_Unbounded_String (To_Ada (Item.Dtype));
               Node_Rec.Rank := Natural (Item.Rank);
               for D in 1 .. Node_Rec.Rank loop
                  Node_Rec.Dims (D) := Long_Long_Integer (Item.Dims (D));
               end loop;
               Node_Rec.N_Elements := Long_Long_Integer (Item.N_Elements);
               Rec.Structure.Append (Node_Rec);
               if To_String (Node_Rec.Path) = "/ECG" then
                  But := True;
               end if;
               if Ends_With (To_String (Node_Rec.Path), "/data/value") then
                  Heart := True;
               end if;
            end if;
         end;
      end loop;
      Rec.Window_Start := Req.Start;
      if But and then Exists (Sess.Handle, "/sampling_freq") then
         Load_But (Rec, Sess.Handle, Req);
      elsif Heart then
         Rec.Comments.Append (To_Unbounded_String ("layout: HeartCycle"));
         Load_Heartcycle (Rec, Sess.Handle, Req);
      else
         Rec.Comments.Append (To_Unbounded_String ("layout: generic HDF5"));
      end if;
   end Read;

end Meddb.Hdf5;
