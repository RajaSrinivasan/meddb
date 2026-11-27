with Ada.Containers;
with Ada.Directories;
with Ada.Finalization;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Interfaces.C;
with Interfaces.C.Strings;
with System;

with Meddb.Types;

package body Meddb.Edf is

   use Ada.Strings.Unbounded;
   use Interfaces.C;
   use Interfaces.C.Strings;

   type File_Ptr is new System.Address;

   function C_Open (Path : chars_ptr; Read_Ann : int; Out_File : access File_Ptr) return int
   with Import => True, Convention => C, External_Name => "meddb_edf_open";

   procedure C_Close (File : File_Ptr)
   with Import => True, Convention => C, External_Name => "meddb_edf_close";

   function C_Error return chars_ptr
   with Import => True, Convention => C, External_Name => "meddb_edf_last_error";

   function C_Filetype (File : File_Ptr) return int
   with Import => True, Convention => C, External_Name => "meddb_edf_filetype";

   function C_Duration (File : File_Ptr) return double
   with Import => True, Convention => C, External_Name => "meddb_edf_duration";

   function C_Nsignals (File : File_Ptr) return int
   with Import => True, Convention => C, External_Name => "meddb_edf_nsignals";

   function C_Nannotations (File : File_Ptr) return long_long
   with Import => True, Convention => C, External_Name => "meddb_edf_nannotations";

   procedure C_Start
     (File : File_Ptr; Year, Month, Day, Hour, Minute, Second : access int;
      Subsecond : access double)
   with Import => True, Convention => C, External_Name => "meddb_edf_start";

   function C_Patient (File : File_Ptr) return chars_ptr
   with Import => True, Convention => C, External_Name => "meddb_edf_patient";

   function C_Recording (File : File_Ptr) return chars_ptr
   with Import => True, Convention => C, External_Name => "meddb_edf_recording";

   function C_Equipment (File : File_Ptr) return chars_ptr
   with Import => True, Convention => C, External_Name => "meddb_edf_equipment";

   function C_Label (File : File_Ptr; Index : int) return chars_ptr
   with Import => True, Convention => C, External_Name => "meddb_edf_label";

   function C_Units (File : File_Ptr; Index : int) return chars_ptr
   with Import => True, Convention => C, External_Name => "meddb_edf_units";

   function C_Transducer (File : File_Ptr; Index : int) return chars_ptr
   with Import => True, Convention => C, External_Name => "meddb_edf_transducer";

   function C_Prefilter (File : File_Ptr; Index : int) return chars_ptr
   with Import => True, Convention => C, External_Name => "meddb_edf_prefilter";

   function C_Fs (File : File_Ptr; Index : int) return double
   with Import => True, Convention => C, External_Name => "meddb_edf_fs";

   function C_Phys_Min (File : File_Ptr; Index : int) return double
   with Import => True, Convention => C, External_Name => "meddb_edf_phys_min";

   function C_Phys_Max (File : File_Ptr; Index : int) return double
   with Import => True, Convention => C, External_Name => "meddb_edf_phys_max";

   function C_Dig_Min (File : File_Ptr; Index : int) return int
   with Import => True, Convention => C, External_Name => "meddb_edf_dig_min";

   function C_Dig_Max (File : File_Ptr; Index : int) return int
   with Import => True, Convention => C, External_Name => "meddb_edf_dig_max";

   function C_Nsamples (File : File_Ptr; Index : int) return long_long
   with Import => True, Convention => C, External_Name => "meddb_edf_nsamples";

   function C_Read
     (File : File_Ptr; Index : int; Start : long_long; Count : int; Buf : System.Address)
      return int
   with Import => True, Convention => C, External_Name => "meddb_edf_read";

   function C_Annotation
     (File : File_Ptr; Index : long_long; Onset, Duration : access double;
      Text : chars_ptr; Text_Cap : int) return int
   with Import => True, Convention => C, External_Name => "meddb_edf_annotation";

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
      return Ada.Strings.Fixed.Trim (Value (P), Ada.Strings.Both);
   end S;

   function Pad (N : Integer) return String is
      Img : constant String := Types.Trim (Integer'Image (N));
   begin
      if Img'Length = 1 then
         return "0" & Img;
      end if;
      return Img;
   end Pad;

   function Format_Name (Kind : int) return String is
   begin
      case Kind is
         when 0 => return "edf";
         when 1 => return "edf+";
         when 2 => return "bdf";
         when 3 => return "bdf+";
         when others => return "edf";
      end case;
   end Format_Name;

   function Open_File (Path : String) return File_Ptr is
      Name : chars_ptr := New_String (Path);
      Handle : aliased File_Ptr := File_Ptr (System.Null_Address);
      Rc : constant int := C_Open (Name, 1, Handle'Access);
   begin
      Free (Name);
      if Rc /= 0 then
         raise Meddb.Error with "cannot open " & Path & ": " & S (C_Error);
      end if;
      return Handle;
   end Open_File;

   procedure Append_Annotations
     (File  : File_Ptr;
      Rec   : in out Types.Recording;
      Start : Long_Float;
      Span  : Long_Float)
   is
      Total : constant Long_Long_Integer := Long_Long_Integer (C_Nannotations (File));
      Limit : constant Long_Long_Integer :=
        Long_Long_Integer'Min (Total, 100_000);
      Wend : constant Long_Float := Start + Span;
   begin
      Rec.Annotations_In_File :=
        Rec.Annotations_In_File + Natural (Long_Long_Integer'Min (Total, Long_Long_Integer (Natural'Last)));
      for Index in 0 .. Limit - 1 loop
         declare
            Onset    : aliased double;
            Duration : aliased double;
            Text     : chars_ptr := New_String ((1 .. 512 => ' '));
            Item     : Types.Annotation;
         begin
            if C_Annotation (File, long_long (Index), Onset'Access, Duration'Access, Text, 512) = 0
            then
               Item.Onset := Long_Float (Onset);
               Item.Duration := Long_Float (Duration);
               Item.Label := To_Unbounded_String (S (Text));
               Item.Description := Item.Label;
               if Span <= 0.0
                 or else (Item.Onset < Wend
                          and then Item.Onset + Item.Duration >= Start)
               then
                  if Span <= 0.0 or else Item.Onset < Wend then
                     Rec.Annotations.Append (Item);
                  end if;
               end if;
            end if;
            Free (Text);
         end;
      end loop;
   end Append_Annotations;

   procedure Read
     (Path      : String;
      Req       : Types.Read_Request;
      Hypnogram : String;
      Rec       : out Types.Recording)
   is
      Sess : Session;
      Ann_Span_Load : Boolean;
      Ann_Span : Long_Float;
   begin
      Rec := (others => <>);
      Sess.Handle := Open_File (Path);
      Rec.Name := To_Unbounded_String (Ada.Directories.Simple_Name (Path));
      Rec.Format_Name := To_Unbounded_String (Format_Name (C_Filetype (Sess.Handle)));
      Rec.Source := To_Unbounded_String (Path);
      Rec.Duration := Long_Float (C_Duration (Sess.Handle));
      declare
         Year, Month, Day, Hour, Minute, Second : aliased int;
         Sub : aliased double;
      begin
         C_Start (Sess.Handle, Year'Access, Month'Access, Day'Access,
                  Hour'Access, Minute'Access, Second'Access, Sub'Access);
         if Year > 0 then
            Rec.Start_Time := To_Unbounded_String
              (Types.Trim (Integer'Image (Integer (Year))) & "-" &
               Pad (Integer (Month)) & "-" & Pad (Integer (Day)) & "T" &
               Pad (Integer (Hour)) & ":" & Pad (Integer (Minute)) & ":" &
               Pad (Integer (Second)));
         end if;
      end;
      declare
         Patient : constant String := S (C_Patient (Sess.Handle));
         Recording : constant String := S (C_Recording (Sess.Handle));
         Equipment : constant String := S (C_Equipment (Sess.Handle));
      begin
         if Patient'Length > 0 then
            Rec.Comments.Append (To_Unbounded_String ("patient: " & Patient));
         end if;
         if Recording'Length > 0 then
            Rec.Comments.Append (To_Unbounded_String ("recording: " & Recording));
         end if;
         if Equipment'Length > 0 then
            Rec.Comments.Append (To_Unbounded_String ("equipment: " & Equipment));
         end if;
      end;

      for Index in 0 .. Integer (C_Nsignals (Sess.Handle)) - 1 loop
         declare
            Ch   : Types.Channel;
            Rate : constant Long_Float := Long_Float (C_Fs (Sess.Handle, int (Index)));
            N    : constant Long_Long_Integer :=
              Long_Long_Integer (C_Nsamples (Sess.Handle, int (Index)));
            Pmin : constant Long_Float := Long_Float (C_Phys_Min (Sess.Handle, int (Index)));
            Pmax : constant Long_Float := Long_Float (C_Phys_Max (Sess.Handle, int (Index)));
            Dmin : constant Integer := Integer (C_Dig_Min (Sess.Handle, int (Index)));
            Dmax : constant Integer := Integer (C_Dig_Max (Sess.Handle, int (Index)));
            Do_Load : Boolean;
            Span : Long_Float;
            Label : constant String := S (C_Label (Sess.Handle, int (Index)));
         begin
            Ch.Label := To_Unbounded_String
              (if Label'Length > 0 then Label
               else "ch" & Types.Trim (Integer'Image (Index + 1)));
            Ch.Units := To_Unbounded_String (S (C_Units (Sess.Handle, int (Index))));
            Ch.Sampling_Rate := Rate;
            Ch.Physical_Min := Pmin;
            Ch.Physical_Max := Pmax;
            Ch.Digital_Min := Dmin;
            Ch.Digital_Max := Dmax;
            if Dmax /= Dmin and then Pmax /= Pmin then
               Ch.Gain := Long_Float (Dmax - Dmin) / (Pmax - Pmin);
            end if;
            Ch.Samples_In_File := N;
            declare
               Sensor : constant String := S (C_Transducer (Sess.Handle, int (Index)));
               Filter : constant String := S (C_Prefilter (Sess.Handle, int (Index)));
            begin
               if Sensor'Length > 0 and then Filter'Length > 0 then
                  Ch.Note := To_Unbounded_String (Sensor & "; " & Filter);
               elsif Sensor'Length > 0 then
                  Ch.Note := To_Unbounded_String (Sensor);
               else
                  Ch.Note := To_Unbounded_String (Filter);
               end if;
            end;
            Types.Decide_Load (Rec.Duration, Rate, Req, Do_Load, Span);
            Types.Add_Channel (Rec, Ch);
            if Do_Load then
               declare
                  Origin : constant Long_Long_Integer :=
                    Types.Start_Index (Rate, Req.Start);
                  Count : constant Long_Long_Integer :=
                    Types.Sample_Count (Rate, Span, N, Req.Start);
                  Data : Types.Sample_Vectors.Vector;
               begin
                  if Count > 0 then
                     Data.Reserve_Capacity (Ada.Containers.Count_Type (Count));
                     declare
                        Remaining : Long_Long_Integer := Count;
                        Cursor    : Long_Long_Integer := Origin;
                     begin
                        while Remaining > 0 loop
                           declare
                              This : constant Integer := Integer
                                (Long_Long_Integer'Min (Remaining, 16_384));
                              Buf : array (1 .. This) of double
                                with Convention => C;
                              Got : int;
                           begin
                              Got := C_Read
                                (Sess.Handle, int (Index), long_long (Cursor),
                                 int (This), Buf'Address);
                              if Got < 0 then
                                 raise Meddb.Error with "cannot read " &
                                   To_String (Ch.Label) & ": " & S (C_Error);
                              end if;
                              exit when Got = 0;
                              for I in 1 .. Integer (Got) loop
                                 Data.Append (Long_Float (Buf (I)));
                              end loop;
                              Cursor := Cursor + Long_Long_Integer (Got);
                              Remaining := Remaining - Long_Long_Integer (Got);
                              exit when Got < int (This);
                           end;
                        end loop;
                     end;
                     Types.Set_Samples
                       (Rec, Positive (Rec.Channels.Last_Index), Data);
                     if Span > Rec.Window_Duration then
                        Rec.Window_Duration := Span;
                     end if;
                  end if;
               end;
            else
               declare
                  Item : Types.Channel := Rec.Channels (Rec.Channels.Last_Index);
               begin
                  if Rate > Types.Fast_Rate_Hz then
                     Item.Note := To_Unbounded_String
                       ("not loaded; pass --duration or --full");
                     Rec.Channels.Replace_Element (Rec.Channels.Last_Index, Item);
                  end if;
               end;
            end if;
         end;
      end loop;
      Rec.Window_Start := Req.Start;
      Types.Decide_Load (Rec.Duration, 1.0, Req, Ann_Span_Load, Ann_Span);
      if Rec.Window_Duration = 0.0 then
         Rec.Window_Duration := Ann_Span;
      end if;
      Append_Annotations (Sess.Handle, Rec, Req.Start, Rec.Window_Duration);
      if Hypnogram'Length > 0 then
         declare
            Extra : Session;
         begin
            Extra.Handle := Open_File (Hypnogram);
            Rec.Comments.Append
              (To_Unbounded_String ("hypnogram: " & Hypnogram));
            Append_Annotations (Extra.Handle, Rec, Req.Start, Rec.Window_Duration);
         end;
      end if;
   end Read;

end Meddb.Edf;
