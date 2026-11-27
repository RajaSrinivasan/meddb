with Ada.Containers;
with Ada.Directories;
with Ada.Finalization;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Interfaces.C;
with Interfaces.C.Strings;
with System;

package body Meddb.Biosig is

   use Ada.Strings.Unbounded;
   use Interfaces.C;
   use Interfaces.C.Strings;

   type File_Ptr is new System.Address;

   function C_Open (Path : chars_ptr; Out_File : access File_Ptr) return int
   with Import => True, Convention => C, External_Name => "meddb_biosig_open";

   procedure C_Close (File : File_Ptr)
   with Import => True, Convention => C, External_Name => "meddb_biosig_close";

   function C_Error return chars_ptr
   with Import => True, Convention => C, External_Name => "meddb_biosig_last_error";

   function C_Format (File : File_Ptr) return chars_ptr
   with Import => True, Convention => C, External_Name => "meddb_biosig_format";

   function C_Patient (File : File_Ptr) return chars_ptr
   with Import => True, Convention => C, External_Name => "meddb_biosig_patient";

   function C_Patient_Id (File : File_Ptr) return chars_ptr
   with Import => True, Convention => C, External_Name => "meddb_biosig_patient_id";

   function C_Recording_Id (File : File_Ptr) return chars_ptr
   with Import => True, Convention => C, External_Name => "meddb_biosig_recording_id";

   function C_Manufacturer (File : File_Ptr) return chars_ptr
   with Import => True, Convention => C, External_Name => "meddb_biosig_manufacturer";

   function C_Model (File : File_Ptr) return chars_ptr
   with Import => True, Convention => C, External_Name => "meddb_biosig_model";

   function C_Version (File : File_Ptr) return chars_ptr
   with Import => True, Convention => C, External_Name => "meddb_biosig_sw_version";

   function C_Serial (File : File_Ptr) return chars_ptr
   with Import => True, Convention => C, External_Name => "meddb_biosig_serial";

   function C_Start (File : File_Ptr) return chars_ptr
   with Import => True, Convention => C, External_Name => "meddb_biosig_start";

   function C_Duration (File : File_Ptr) return double
   with Import => True, Convention => C, External_Name => "meddb_biosig_duration";

   function C_Nsignals (File : File_Ptr) return int
   with Import => True, Convention => C, External_Name => "meddb_biosig_nsignals";

   function C_Label (File : File_Ptr; Index : int) return chars_ptr
   with Import => True, Convention => C, External_Name => "meddb_biosig_label";

   function C_Units (File : File_Ptr; Index : int) return chars_ptr
   with Import => True, Convention => C, External_Name => "meddb_biosig_units";

   function C_Transducer (File : File_Ptr; Index : int) return chars_ptr
   with Import => True, Convention => C, External_Name => "meddb_biosig_transducer";

   function C_Fs (File : File_Ptr; Index : int) return double
   with Import => True, Convention => C, External_Name => "meddb_biosig_fs";

   function C_Cal (File : File_Ptr; Index : int) return double
   with Import => True, Convention => C, External_Name => "meddb_biosig_cal";

   function C_Off (File : File_Ptr; Index : int) return double
   with Import => True, Convention => C, External_Name => "meddb_biosig_off";

   function C_Phys_Min (File : File_Ptr; Index : int) return double
   with Import => True, Convention => C, External_Name => "meddb_biosig_phys_min";

   function C_Phys_Max (File : File_Ptr; Index : int) return double
   with Import => True, Convention => C, External_Name => "meddb_biosig_phys_max";

   function C_Dig_Min (File : File_Ptr; Index : int) return int
   with Import => True, Convention => C, External_Name => "meddb_biosig_dig_min";

   function C_Dig_Max (File : File_Ptr; Index : int) return int
   with Import => True, Convention => C, External_Name => "meddb_biosig_dig_max";

   function C_Lead (File : File_Ptr; Index : int) return int
   with Import => True, Convention => C, External_Name => "meddb_biosig_lead";

   function C_Nsamples (File : File_Ptr; Index : int) return long_long
   with Import => True, Convention => C, External_Name => "meddb_biosig_nsamples";

   function C_Read
     (File : File_Ptr; Index : int; Start : long_long; Count : int; Buf : System.Address)
      return int
   with Import => True, Convention => C, External_Name => "meddb_biosig_read";

   function C_Nevents (File : File_Ptr) return int
   with Import => True, Convention => C, External_Name => "meddb_biosig_nevents";

   function C_Event
     (File : File_Ptr; Index : int; Onset, Duration : access double; Channel : access int;
      Label : chars_ptr; Label_Cap : int; Desc : chars_ptr; Desc_Cap : int) return int
   with Import => True, Convention => C, External_Name => "meddb_biosig_event";

   function C_Nstatements (File : File_Ptr) return int
   with Import => True, Convention => C, External_Name => "meddb_biosig_nstatements";

   function C_Statement (File : File_Ptr; Index : int) return chars_ptr
   with Import => True, Convention => C, External_Name => "meddb_biosig_statement";

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

   function Blank_Id (Text : String) return Boolean is
   begin
      if Text'Length = 0 then
         return True;
      end if;
      for C of Text loop
         if C /= '0' and then C /= ' ' then
            return False;
         end if;
      end loop;
      return True;
   end Blank_Id;

   procedure Add_Comment (Rec : in out Types.Recording; Text : String) is
   begin
      if Text'Length > 0 then
         Rec.Comments.Append (To_Unbounded_String (Text));
      end if;
   end Add_Comment;

   procedure Read
     (Path        : String;
      Req         : Types.Read_Request;
      Expect      : String;
      Want_Events : Boolean;
      Rec         : out Types.Recording)
   is
      Sess : Session;
      Name : chars_ptr := New_String (Path);
      Handle : aliased File_Ptr := File_Ptr (System.Null_Address);
      Rc : int;
      Ann_Load : Boolean;
      Ann_Span : Long_Float;
   begin
      Rec := (others => <>);
      Rc := C_Open (Name, Handle'Access);
      Free (Name);
      Name := Null_Ptr;
      if Rc /= 0 then
         raise Meddb.Error with "cannot open " & Path & ": " & S (C_Error);
      end if;
      Sess.Handle := Handle;
      declare
         Kind : constant String := S (C_Format (Sess.Handle));
      begin
         if Expect'Length > 0 and then Kind /= Expect then
            raise Meddb.Error with
              Path & " is " & Kind & ", expected " & Expect;
         end if;
         Rec.Format_Name := To_Unbounded_String (Kind);
      end;
      Rec.Name := To_Unbounded_String (Ada.Directories.Simple_Name (Path));
      Rec.Source := To_Unbounded_String (Path);
      Rec.Start_Time := To_Unbounded_String (S (C_Start (Sess.Handle)));
      Rec.Duration := Long_Float (C_Duration (Sess.Handle));

      declare
         Patient : constant String := S (C_Patient (Sess.Handle));
         Ident   : constant String := S (C_Patient_Id (Sess.Handle));
         Rec_Id  : constant String := S (C_Recording_Id (Sess.Handle));
         Maker   : constant String := S (C_Manufacturer (Sess.Handle));
         Model   : constant String := S (C_Model (Sess.Handle));
         Version : constant String := S (C_Version (Sess.Handle));
         Serial  : constant String := S (C_Serial (Sess.Handle));
         Device  : Unbounded_String;
      begin
         if Patient'Length > 0 and then Ident'Length > 0 then
            Add_Comment (Rec, "patient: " & Patient & " id=" & Ident);
         elsif Patient'Length > 0 then
            Add_Comment (Rec, "patient: " & Patient);
         elsif Ident'Length > 0 then
            Add_Comment (Rec, "patient_id: " & Ident);
         end if;
         if not Blank_Id (Rec_Id) then
            Add_Comment (Rec, "recording_id: " & Rec_Id);
         end if;
         if Maker'Length > 0 then
            Append (Device, Maker);
         end if;
         if Model'Length > 0 then
            if Device /= "" then
               Append (Device, " ");
            end if;
            Append (Device, Model);
         end if;
         if Version'Length > 0 then
            if Device /= "" then
               Append (Device, " ");
            end if;
            Append (Device, Version);
         end if;
         if Serial'Length > 0 then
            if Device /= "" then
               Append (Device, " ");
            end if;
            Append (Device, Serial);
         end if;
         if Device /= "" then
            Add_Comment (Rec, "device: " & To_String (Device));
         end if;
      end;

      for Index in 0 .. Integer (C_Nstatements (Sess.Handle)) - 1 loop
         Add_Comment (Rec, "statement: " & S (C_Statement (Sess.Handle, int (Index))));
      end loop;

      for Index in 0 .. Integer (C_Nsignals (Sess.Handle)) - 1 loop
         declare
            Ch    : Types.Channel;
            Rate  : constant Long_Float := Long_Float (C_Fs (Sess.Handle, int (Index)));
            N     : constant Long_Long_Integer :=
              Long_Long_Integer (C_Nsamples (Sess.Handle, int (Index)));
            Label : constant String := S (C_Label (Sess.Handle, int (Index)));
            Lead  : constant Integer := Integer (C_Lead (Sess.Handle, int (Index)));
            Sensor : constant String := S (C_Transducer (Sess.Handle, int (Index)));
            Do_Load : Boolean;
            Span : Long_Float;
         begin
            Ch.Label := To_Unbounded_String
              (if Label'Length > 0 then Label
               else "ch" & Types.Trim (Integer'Image (Index + 1)));
            Ch.Units := To_Unbounded_String (S (C_Units (Sess.Handle, int (Index))));
            Ch.Sampling_Rate := Rate;
            Ch.Physical_Min := Long_Float (C_Phys_Min (Sess.Handle, int (Index)));
            Ch.Physical_Max := Long_Float (C_Phys_Max (Sess.Handle, int (Index)));
            Ch.Digital_Min := Integer (C_Dig_Min (Sess.Handle, int (Index)));
            Ch.Digital_Max := Integer (C_Dig_Max (Sess.Handle, int (Index)));
            Ch.Gain := Long_Float (C_Cal (Sess.Handle, int (Index)));
            Ch.Baseline := Integer (C_Off (Sess.Handle, int (Index)));
            Ch.Samples_In_File := N;
            if Lead /= 0 and then Sensor'Length > 0 then
               Ch.Note := To_Unbounded_String
                 ("lead=" & Types.Trim (Integer'Image (Lead)) & "; " & Sensor);
            elsif Lead /= 0 then
               Ch.Note := To_Unbounded_String
                 ("lead=" & Types.Trim (Integer'Image (Lead)));
            else
               Ch.Note := To_Unbounded_String (Sensor);
            end if;
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
            end if;
         end;
      end loop;

      Rec.Window_Start := Req.Start;
      Types.Decide_Load (Rec.Duration, 1.0, Req, Ann_Load, Ann_Span);
      if Rec.Window_Duration = 0.0 then
         Rec.Window_Duration := Ann_Span;
      end if;

      if Want_Events then
         declare
            Total : constant Integer := Integer (C_Nevents (Sess.Handle));
            Wend  : constant Long_Float := Req.Start + Rec.Window_Duration;
         begin
            Rec.Annotations_In_File := Total;
            for Index in 0 .. Total - 1 loop
               declare
                  Onset    : aliased double;
                  Duration : aliased double;
                  Channel  : aliased int;
                  Label    : chars_ptr := New_String ((1 .. 255 => ' '));
                  Desc     : chars_ptr := New_String ((1 .. 255 => ' '));
                  Item     : Types.Annotation;
               begin
                  if C_Event
                    (Sess.Handle, int (Index), Onset'Access, Duration'Access,
                     Channel'Access, Label, 256, Desc, 256) = 0
                  then
                     Item.Onset := Long_Float (Onset);
                     Item.Duration := Long_Float (Duration);
                     Item.Label := To_Unbounded_String (S (Label));
                     Item.Description := To_Unbounded_String (S (Desc));
                     if Channel /= 0 then
                        Item.Channel := To_Unbounded_String
                          (Types.Trim (Integer'Image (Integer (Channel))));
                     end if;
                     if Rec.Window_Duration <= 0.0
                       or else (Item.Onset < Wend
                                and then Item.Onset + Item.Duration >= Req.Start)
                     then
                        Rec.Annotations.Append (Item);
                     end if;
                  end if;
                  Free (Label);
                  Free (Desc);
               end;
            end loop;
         end;
      end if;
   end Read;

end Meddb.Biosig;
