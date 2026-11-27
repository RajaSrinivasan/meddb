with Ada.Containers;
with Ada.Directories;
with Ada.Finalization;
with Ada.Strings.Unbounded;
with Ada.Unchecked_Conversion;
with Interfaces.C;
with Interfaces.C.Strings;
with System;
with System.Storage_Elements;

with Meddb.Hea;
with Meddb.Types;

package body Meddb.Mat is

   use Ada.Strings.Unbounded;
   use type Ada.Containers.Count_Type;
   use Interfaces.C;
   use Interfaces.C.Strings;

   type File_Ptr is new System.Address;

   function C_Open (Path : chars_ptr; Out_File : access File_Ptr) return int
   with Import => True, Convention => C, External_Name => "meddb_mat_open";

   procedure C_Close (File : File_Ptr)
   with Import => True, Convention => C, External_Name => "meddb_mat_close";

   function C_Error return chars_ptr
   with Import => True, Convention => C, External_Name => "meddb_mat_last_error";

   function C_Nvars (File : File_Ptr) return int
   with Import => True, Convention => C, External_Name => "meddb_mat_nvars";

   function C_Name (File : File_Ptr; Index : int) return chars_ptr
   with Import => True, Convention => C, External_Name => "meddb_mat_name";

   function C_Info
     (File : File_Ptr; Index : int; Rank : access int;
      D0, D1 : access unsigned_long;
      Class_Type, Numeric : access int;
      N_Elem : access unsigned_long) return int
   with Import => True, Convention => C, External_Name => "meddb_mat_info";

   function C_Read
     (File : File_Ptr; Index : int; Data : access System.Address;
      D0, D1 : access unsigned_long; Rank : access int) return int
   with Import => True, Convention => C, External_Name => "meddb_mat_read";

   procedure C_Free (Ptr : System.Address)
   with Import => True, Convention => C, External_Name => "meddb_mat_free";

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

   function Elem (Base : System.Address; Index : Long_Long_Integer) return double is
      use System.Storage_Elements;
      type Elem_Ptr is access all double
      with Convention => C, Storage_Size => 0;
      function To_Ptr is new Ada.Unchecked_Conversion (System.Address, Elem_Ptr);
   begin
      return To_Ptr (Base + Storage_Offset (Index) * (double'Size / System.Storage_Unit))
        .all;
   end Elem;

   procedure Read
     (Path     : String;
      Req      : Types.Read_Request;
      Hea_Path : String;
      Rec      : out Types.Recording)
   is
      Sess : Session;
      Name : chars_ptr := New_String (Path);
      Handle : aliased File_Ptr := File_Ptr (System.Null_Address);
      Chosen : Integer := -1;
      Best_N : unsigned_long := 0;
      Hea : constant String :=
        (if Hea_Path'Length > 0 then Hea_Path else Meddb.Hea.Sibling_Hea (Path));
   begin
      Rec := (others => <>);
      if C_Open (Name, Handle'Access) /= 0 then
         Free (Name);
         raise Meddb.Error with "cannot open " & Path & ": " & S (C_Error);
      end if;
      Free (Name);
      Sess.Handle := Handle;
      Rec.Format_Name := To_Unbounded_String ("mat");
      Rec.Source := To_Unbounded_String (Path);
      Rec.Name := To_Unbounded_String (Ada.Directories.Simple_Name (Path));
      for Index in 0 .. Integer (C_Nvars (Sess.Handle)) - 1 loop
         declare
            Rank : aliased int;
            D0, D1, N_Elem : aliased unsigned_long;
            Class_Type, Numeric : aliased int;
            Node : Types.Structure_Node;
            Var_Name : constant String := S (C_Name (Sess.Handle, int (Index)));
         begin
            if C_Info (Sess.Handle, int (Index), Rank'Access, D0'Access, D1'Access,
                       Class_Type'Access, Numeric'Access, N_Elem'Access) = 0
            then
               Node.Path := To_Unbounded_String (Var_Name);
               Node.Dtype := To_Unbounded_String
                 ("class " & Types.Trim (Integer'Image (Integer (Class_Type))));
               Node.Rank := Natural (Rank);
               Node.Dims (1) := Long_Long_Integer (D0);
               if Rank >= 2 then
                  Node.Dims (2) := Long_Long_Integer (D1);
               end if;
               Node.N_Elements := Long_Long_Integer (N_Elem);
               Rec.Structure.Append (Node);
               if Numeric /= 0 then
                  if Var_Name = "val" then
                     Chosen := Index;
                     Best_N := N_Elem;
                  elsif Chosen < 0 or else (S (C_Name (Sess.Handle, int (Chosen))) /= "val"
                                            and then N_Elem > Best_N)
                  then
                     Chosen := Index;
                     Best_N := N_Elem;
                  end if;
               end if;
            end if;
         end;
      end loop;
      if Chosen < 0 then
         raise Meddb.Error with "no numeric matrix in " & Path;
      end if;
      if Ada.Directories.Exists (Hea) then
         Meddb.Hea.Load (Hea, Rec);
         Rec.Comments.Append (To_Unbounded_String ("hea: " & Hea));
      else
         Rec.Comments.Append
           (To_Unbounded_String ("no companion .hea; sample index used as time"));
      end if;

      declare
         Data : aliased System.Address := System.Null_Address;
         D0, D1 : aliased unsigned_long;
         Rank : aliased int;
         Nchan, Nsamp : Long_Long_Integer;
         Rows_Are_Channels : Boolean;
      begin
         if C_Read (Sess.Handle, int (Chosen), Data'Access, D0'Access, D1'Access,
                    Rank'Access) /= 0
         then
            raise Meddb.Error with "cannot read MATLAB variable: " & S (C_Error);
         end if;
         if Rank < 2 then
            Nchan := 1;
            Nsamp := Long_Long_Integer (D0);
            Rows_Are_Channels := True;
         elsif Rec.Channels.Length = Ada.Containers.Count_Type (D0) then
            Nchan := Long_Long_Integer (D0);
            Nsamp := Long_Long_Integer (D1);
            Rows_Are_Channels := True;
         elsif Rec.Channels.Length = Ada.Containers.Count_Type (D1) then
            Nchan := Long_Long_Integer (D1);
            Nsamp := Long_Long_Integer (D0);
            Rows_Are_Channels := False;
         elsif D0 <= D1 and then D0 <= 64 then
            Nchan := Long_Long_Integer (D0);
            Nsamp := Long_Long_Integer (D1);
            Rows_Are_Channels := True;
         else
            Nchan := Long_Long_Integer (D1);
            Nsamp := Long_Long_Integer (D0);
            Rows_Are_Channels := False;
         end if;
         if Rec.Channels.Length /= Ada.Containers.Count_Type (Nchan) then
            declare
               Old : constant Types.Channel_Vectors.Vector := Rec.Channels;
               Fs : Long_Float := 0.0;
            begin
               if not Old.Is_Empty then
                  Fs := Old (Old.First_Index).Sampling_Rate;
               end if;
               Rec.Channels.Clear;
               Rec.Samples.Clear;
               for C in 1 .. Positive (Nchan) loop
                  declare
                     Ch : Types.Channel;
                  begin
                     if C <= Positive (Old.Length) then
                        Ch := Old (C);
                     else
                        Ch.Label := To_Unbounded_String
                          ("ch" & Types.Trim (Integer'Image (C)));
                        Ch.Sampling_Rate := Fs;
                     end if;
                     Ch.Samples_In_File := Nsamp;
                     Types.Add_Channel (Rec, Ch);
                  end;
               end loop;
            end;
         end if;
         declare
            Fs : Long_Float := 0.0;
            Do_Load : Boolean;
            Span : Long_Float;
            Origin : Long_Long_Integer;
            Count : Long_Long_Integer;
         begin
            if not Rec.Channels.Is_Empty then
               Fs := Rec.Channels (Rec.Channels.First_Index).Sampling_Rate;
            end if;
            if Fs <= 0.0 then
               Fs := 1.0;
               for Index in Rec.Channels.First_Index .. Rec.Channels.Last_Index loop
                  declare
                     Ch : Types.Channel := Rec.Channels (Index);
                  begin
                     Ch.Sampling_Rate := Fs;
                     Ch.Units := To_Unbounded_String ("adu");
                     Rec.Channels.Replace_Element (Index, Ch);
                  end;
               end loop;
            end if;
            Rec.Duration := Long_Float (Nsamp) / Fs;
            for Index in Rec.Channels.First_Index .. Rec.Channels.Last_Index loop
               declare
                  Ch : Types.Channel := Rec.Channels (Index);
               begin
                  Ch.Samples_In_File := Nsamp;
                  if Ch.Sampling_Rate <= 0.0 then
                     Ch.Sampling_Rate := Fs;
                  end if;
                  Rec.Channels.Replace_Element (Index, Ch);
               end;
            end loop;
            Types.Decide_Load (Rec.Duration, Fs, Req, Do_Load, Span);
            Rec.Window_Start := Req.Start;
            Rec.Window_Duration := Span;
            if Do_Load then
               Origin := Types.Start_Index (Fs, Req.Start);
               Count := Types.Sample_Count (Fs, Span, Nsamp, Req.Start);
               for C in 0 .. Nchan - 1 loop
                  declare
                     Data_V : Types.Sample_Vectors.Vector;
                     Ch : constant Types.Channel :=
                       Rec.Channels (Positive (C + 1));
                  begin
                     Data_V.Reserve_Capacity (Ada.Containers.Count_Type (Count));
                     for S in Origin .. Origin + Count - 1 loop
                        declare
                           Raw_Index : Long_Long_Integer;
                           Raw : Long_Float;
                           Phys : Long_Float;
                        begin
                           if Rows_Are_Channels then
                              Raw_Index := C + S * Nchan;
                           else
                              Raw_Index := S + C * Nsamp;
                           end if;
                           Raw := Long_Float (Elem (Data, Raw_Index));
                           if Ch.Gain /= 0.0 then
                              Phys := (Raw - Long_Float (Ch.Baseline)) / Ch.Gain;
                           else
                              Phys := Raw;
                           end if;
                           Data_V.Append (Phys);
                        end;
                     end loop;
                     Types.Set_Samples (Rec, Positive (C + 1), Data_V);
                  end;
               end loop;
            end if;
         end;
         C_Free (Data);
      end;
   end Read;

end Meddb.Mat;
