with Ada.Exceptions;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Ada.Text_IO;

with Meddb.Types;

package body Meddb.Hea is

   use Ada.Strings.Unbounded;

   function Sibling_Hea (Signal_Path : String) return String is
      Dot : constant Natural := Ada.Strings.Fixed.Index
        (Signal_Path, ".", Ada.Strings.Backward);
   begin
      if Dot > Signal_Path'First then
         return Signal_Path (Signal_Path'First .. Dot - 1) & ".hea";
      end if;
      return Signal_Path & ".hea";
   end Sibling_Hea;

   function Is_Integer_Token (S : String) return Boolean is
      First : Positive := S'First;
   begin
      if S'Length = 0 then
         return False;
      end if;
      if S (First) = '+' or else S (First) = '-' then
         First := First + 1;
      end if;
      if First > S'Last then
         return False;
      end if;
      for C of S (First .. S'Last) loop
         if C not in '0' .. '9' then
            return False;
         end if;
      end loop;
      return True;
   end Is_Integer_Token;

   procedure Parse_Gain
     (Token        : String;
      Gain         : out Long_Float;
      Baseline     : out Integer;
      Units        : out Unbounded_String;
      Baseline_Set : out Boolean)
   is
      Open_P  : constant Natural := Ada.Strings.Fixed.Index (Token, "(");
      Close_P : constant Natural := Ada.Strings.Fixed.Index (Token, ")");
      Slash   : constant Natural := Ada.Strings.Fixed.Index (Token, "/");
      Num_End : Positive := Token'Last;
   begin
      Gain := 0.0;
      Baseline := 0;
      Units := Null_Unbounded_String;
      Baseline_Set := False;
      if Open_P > Token'First then
         Num_End := Open_P - 1;
      elsif Slash > Token'First then
         Num_End := Slash - 1;
      end if;
      if Num_End >= Token'First then
         Gain := Long_Float'Value (Token (Token'First .. Num_End));
      end if;
      if Open_P > 0 and then Close_P > Open_P then
         Baseline := Integer'Value (Token (Open_P + 1 .. Close_P - 1));
         Baseline_Set := True;
      end if;
      if Slash > 0 and then Slash < Token'Last then
         Units := To_Unbounded_String (Token (Slash + 1 .. Token'Last));
      end if;
   end Parse_Gain;

   function Next_Token (Line : String; From : in out Positive) return String is
      First : Positive;
   begin
      while From <= Line'Last and then Line (From) = ' ' loop
         From := From + 1;
      end loop;
      if From > Line'Last then
         return "";
      end if;
      First := From;
      while From <= Line'Last and then Line (From) /= ' ' loop
         From := From + 1;
      end loop;
      return Line (First .. From - 1);
   end Next_Token;

   procedure Load (Path : String; Rec : in out Types.Recording) is
      File    : Ada.Text_IO.File_Type;
      First   : Boolean := True;
      Fs      : Long_Float := 0.0;
      Nsamp   : Long_Long_Integer := 0;
      Rec_Name : Unbounded_String;
   begin
      begin
         Ada.Text_IO.Open (File, Ada.Text_IO.In_File, Path);
      exception
         when others =>
            raise Meddb.Error with "cannot open WFDB header " & Path;
      end;
      while not Ada.Text_IO.End_Of_File (File) loop
         declare
            Line : constant String := Ada.Text_IO.Get_Line (File);
            Pos  : Positive := Line'First;
         begin
            if Line'Length = 0 then
               null;
            elsif Line (Line'First) = '#' then
               Rec.Comments.Append
                 (To_Unbounded_String
                    (Ada.Strings.Fixed.Trim (Line (Line'First + 1 .. Line'Last),
                                             Ada.Strings.Both)));
            elsif First then
               First := False;
               declare
                  Name_Tok : constant String := Next_Token (Line, Pos);
                  Nsig_Tok : constant String := Next_Token (Line, Pos);
                  Fs_Tok   : constant String := Next_Token (Line, Pos);
                  Ns_Tok   : constant String := Next_Token (Line, Pos);
                  Extra    : Unbounded_String := Null_Unbounded_String;
               begin
                  pragma Unreferenced (Nsig_Tok);
                  Rec_Name := To_Unbounded_String (Name_Tok);
                  if Fs_Tok'Length > 0 then
                     Fs := Long_Float'Value (Fs_Tok);
                  end if;
                  if Ns_Tok'Length > 0 then
                     Nsamp := Long_Long_Integer'Value (Ns_Tok);
                  end if;
                  while Pos <= Line'Last loop
                     declare
                        Tok : constant String := Next_Token (Line, Pos);
                     begin
                        exit when Tok'Length = 0;
                        if Extra /= "" then
                           Append (Extra, " ");
                        end if;
                        Append (Extra, Tok);
                     end;
                  end loop;
                  if Extra /= "" then
                     Rec.Start_Time := Extra;
                  end if;
               end;
            else
               declare
                  File_Tok : constant String := Next_Token (Line, Pos);
                  Fmt_Tok  : constant String := Next_Token (Line, Pos);
                  Gain_Tok : constant String := Next_Token (Line, Pos);
                  Ch       : Types.Channel;
                  Gain     : Long_Float;
                  Baseline : Integer;
                  Units    : Unbounded_String;
                  Have_Bl  : Boolean;
                  Seen_Int : Natural := 0;
                  Adc_Zero : Integer := 0;
                  Desc     : Unbounded_String := Null_Unbounded_String;
                  pragma Unreferenced (File_Tok, Fmt_Tok);
               begin
                  Parse_Gain (Gain_Tok, Gain, Baseline, Units, Have_Bl);
                  while Pos <= Line'Last loop
                     declare
                        Tok : constant String := Next_Token (Line, Pos);
                     begin
                        exit when Tok'Length = 0;
                        if Seen_Int < 5 and then Is_Integer_Token (Tok) then
                           Seen_Int := Seen_Int + 1;
                           if Seen_Int = 2 then
                              Adc_Zero := Integer'Value (Tok);
                           end if;
                        else
                           if Desc /= "" then
                              Append (Desc, " ");
                           end if;
                           Append (Desc, Tok);
                           while Pos <= Line'Last loop
                              declare
                                 Rest : constant String := Next_Token (Line, Pos);
                              begin
                                 exit when Rest'Length = 0;
                                 Append (Desc, " ");
                                 Append (Desc, Rest);
                              end;
                           end loop;
                        end if;
                     end;
                  end loop;
                  if not Have_Bl then
                     Baseline := Adc_Zero;
                  end if;
                  if Desc = "" then
                     Desc := To_Unbounded_String
                       ("ch" & Types.Trim (Integer'Image
                          (Natural (Rec.Channels.Length) + 1)));
                  end if;
                  Ch.Label := Desc;
                  Ch.Units := Units;
                  Ch.Sampling_Rate := Fs;
                  Ch.Gain := Gain;
                  Ch.Baseline := Baseline;
                  Ch.Samples_In_File := Nsamp;
                  Types.Add_Channel (Rec, Ch);
               end;
            end if;
         end;
      end loop;
      Ada.Text_IO.Close (File);
      if Rec.Name = "" then
         Rec.Name := Rec_Name;
      end if;
      if Fs > 0.0 and then Nsamp > 0 then
         Rec.Duration := Long_Float (Nsamp) / Fs;
      end if;
   exception
      when Meddb.Error =>
         if Ada.Text_IO.Is_Open (File) then
            Ada.Text_IO.Close (File);
         end if;
         raise;
      when E : others =>
         if Ada.Text_IO.Is_Open (File) then
            Ada.Text_IO.Close (File);
         end if;
         raise Meddb.Error with "invalid WFDB header " & Path & ": " &
           Ada.Exceptions.Exception_Message (E);
   end Load;

end Meddb.Hea;
