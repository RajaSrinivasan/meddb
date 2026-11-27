with Ada.Finalization;
with Ada.Strings.Unbounded;
with Interfaces.C;
with Interfaces.C.Strings;
with System;

with Meddb.Biosig;

package body Meddb.Aecg is

   use Ada.Strings.Unbounded;
   use Interfaces.C;
   use Interfaces.C.Strings;

   type Notes_Ptr is new System.Address;

   function C_Load (Path : chars_ptr; Out_Notes : access Notes_Ptr) return int
   with Import => True, Convention => C, External_Name => "meddb_aecg_notes_load";

   procedure C_Free (Notes : Notes_Ptr)
   with Import => True, Convention => C, External_Name => "meddb_aecg_notes_free";

   function C_Error return chars_ptr
   with Import => True, Convention => C, External_Name => "meddb_aecg_notes_last_error";

   function C_Count (Notes : Notes_Ptr) return int
   with Import => True, Convention => C, External_Name => "meddb_aecg_notes_count";

   function C_Overlay (Notes : Notes_Ptr; Index : int) return int
   with Import => True, Convention => C, External_Name => "meddb_aecg_notes_overlay";

   function C_Onset (Notes : Notes_Ptr; Index : int) return double
   with Import => True, Convention => C, External_Name => "meddb_aecg_notes_onset";

   function C_Duration (Notes : Notes_Ptr; Index : int) return double
   with Import => True, Convention => C, External_Name => "meddb_aecg_notes_duration";

   function C_Label (Notes : Notes_Ptr; Index : int) return chars_ptr
   with Import => True, Convention => C, External_Name => "meddb_aecg_notes_label";

   function C_Description (Notes : Notes_Ptr; Index : int) return chars_ptr
   with Import => True, Convention => C, External_Name => "meddb_aecg_notes_description";

   function C_Channel (Notes : Notes_Ptr; Index : int) return chars_ptr
   with Import => True, Convention => C, External_Name => "meddb_aecg_notes_channel";

   type Holder is new Ada.Finalization.Limited_Controlled with record
      Notes : Notes_Ptr := Notes_Ptr (System.Null_Address);
   end record;

   overriding procedure Finalize (Item : in out Holder);

   overriding procedure Finalize (Item : in out Holder) is
   begin
      if Item.Notes /= Notes_Ptr (System.Null_Address) then
         C_Free (Item.Notes);
         Item.Notes := Notes_Ptr (System.Null_Address);
      end if;
   end Finalize;

   function S (P : chars_ptr) return String is
   begin
      if P = Null_Ptr then
         return "";
      end if;
      return Value (P);
   end S;

   procedure Read
     (Path : String;
      Req  : Types.Read_Request;
      Rec  : out Types.Recording)
   is
      Keep : Holder;
      Name : chars_ptr := New_String (Path);
      Notes : aliased Notes_Ptr := Notes_Ptr (System.Null_Address);
      Wend : Long_Float;
   begin
      Biosig.Read (Path, Req, "HL7aECG", False, Rec);
      Rec.Format_Name := To_Unbounded_String ("hl7-aecg");
      Rec.Comments.Append
        (To_Unbounded_String
           ("note: no public real clinical aECG corpus was available as of 26 Nov 2026; "
            & "this reader was checked on the official HL7 2003-12 schema fixture"));
      if C_Load (Name, Notes'Access) /= 0 then
         Free (Name);
         raise Meddb.Error with "cannot read aECG annotations: " & S (C_Error);
      end if;
      Free (Name);
      Keep.Notes := Notes;
      Wend := Rec.Window_Start + Rec.Window_Duration;
      Rec.Annotations_In_File := Integer (C_Count (Keep.Notes));
      for Index in 0 .. Integer (C_Count (Keep.Notes)) - 1 loop
         declare
            Item : Types.Annotation;
            Overlay : constant Boolean := C_Overlay (Keep.Notes, int (Index)) /= 0;
         begin
            Item.Onset := Long_Float (C_Onset (Keep.Notes, int (Index)));
            Item.Duration := Long_Float (C_Duration (Keep.Notes, int (Index)));
            Item.Label := To_Unbounded_String (S (C_Label (Keep.Notes, int (Index))));
            Item.Description := To_Unbounded_String
              (S (C_Description (Keep.Notes, int (Index))));
            Item.Channel := To_Unbounded_String (S (C_Channel (Keep.Notes, int (Index))));
            if Overlay then
               if Rec.Window_Duration <= 0.0
                 or else (Item.Onset < Wend
                          and then Item.Onset + Item.Duration >= Rec.Window_Start)
               then
                  Rec.Annotations.Append (Item);
               end if;
            else
               declare
                  Text : Unbounded_String := Item.Label;
                  Seen : Boolean := False;
               begin
                  if Item.Description /= "" then
                     Append (Text, " (");
                     Append (Text, Item.Description);
                     Append (Text, ")");
                  end if;
                  if Item.Duration > 0.0 or else Item.Onset /= 0.0 then
                     Append (Text, " @ ");
                     Append (Text, Types.Format_Number (Item.Onset));
                     Append (Text, "s");
                     if Item.Duration > 0.0 then
                        Append (Text, " for ");
                        Append (Text, Types.Format_Number (Item.Duration));
                        Append (Text, "s");
                     end if;
                  end if;
                  for Existing of Rec.Comments loop
                     if Existing = Text then
                        Seen := True;
                        exit;
                     end if;
                  end loop;
                  if not Seen then
                     Rec.Comments.Append (Text);
                  end if;
               end;
            end if;
         end;
      end loop;
   end Read;

end Meddb.Aecg;
