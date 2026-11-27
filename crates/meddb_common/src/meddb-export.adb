with Ada.Containers;
with Ada.Directories;
with Ada.Exceptions;
with Ada.Strings.Unbounded;
with Ada.Text_IO;

with Meddb.Types;

package body Meddb.Export is

   use Ada.Strings.Unbounded;

   function Json_Escape (S : String) return String is
      Result : Unbounded_String;
   begin
      for C of S loop
         case C is
            when '"' | '\' =>
               Append (Result, '\');
               Append (Result, C);
            when ASCII.LF =>
               Append (Result, "\n");
            when ASCII.CR =>
               Append (Result, "\r");
            when ASCII.HT =>
               Append (Result, "\t");
            when others =>
               if Character'Pos (C) < 32 then
                  declare
                     Hex : constant String := "0123456789abcdef";
                     V   : constant Natural := Character'Pos (C);
                  begin
                     Append (Result, "\u00");
                     Append (Result, Hex (Hex'First + V / 16));
                     Append (Result, Hex (Hex'First + V mod 16));
                  end;
               else
                  Append (Result, C);
               end if;
         end case;
      end loop;
      return To_String (Result);
   end Json_Escape;

   function Csv_Escape (S : String) return String is
      Needs : Boolean := False;
   begin
      for C of S loop
         if C = ',' or else C = '"' or else C = ASCII.LF or else C = ASCII.CR then
            Needs := True;
            exit;
         end if;
      end loop;
      if not Needs then
         return S;
      end if;
      declare
         Result : Unbounded_String;
      begin
         Append (Result, '"');
         for C of S loop
            if C = '"' then
               Append (Result, '"');
            end if;
            Append (Result, C);
         end loop;
         Append (Result, '"');
         return To_String (Result);
      end;
   end Csv_Escape;

   function Column_Name (Rec : Types.Recording; Index : Positive) return String is
      Ch    : constant Types.Channel := Rec.Channels (Index);
      Label : constant String := To_String (Ch.Label);
      Dup   : Boolean := False;
   begin
      for J in Rec.Channels.First_Index .. Rec.Channels.Last_Index loop
         if J /= Index
           and then Rec.Channels (J).Loaded
           and then Rec.Channels (J).Label = Ch.Label
         then
            Dup := True;
            exit;
         end if;
      end loop;
      if Dup then
         return Label & "@" & Types.Format_Number (Ch.Sampling_Rate, 3) & "Hz";
      end if;
      return Label;
   end Column_Name;

   procedure Put_Json_String
     (File : Ada.Text_IO.File_Type;
      Key  : String;
      Val  : String;
      Tail : String := "")
   is
   begin
      Ada.Text_IO.Put_Line
        (File,
         "  """ & Key & """: """ & Json_Escape (Val) & """" & Tail);
   end Put_Json_String;

   procedure Write (Rec : Types.Recording; Prefix : String) is
      Dir  : constant String := Ada.Directories.Containing_Directory
        (if Prefix'Length > 0 and then
           (Prefix (Prefix'Last) = '/' or else Prefix (Prefix'Last) = '\')
         then Prefix & "x"
         else Prefix);
      Stem : constant String :=
        (if Prefix'Length > 0 and then
           (Prefix (Prefix'Last) = '/' or else Prefix (Prefix'Last) = '\')
         then Prefix & "recording"
         else Prefix);
      Json : Ada.Text_IO.File_Type;
      Csv  : Ada.Text_IO.File_Type;
      Ref  : Long_Float := 0.0;
      Span : Long_Float := 0.0;
   begin
      if Dir /= "" and then Dir /= "." then
         Ada.Directories.Create_Path (Dir);
      end if;

      for Index in Rec.Channels.First_Index .. Rec.Channels.Last_Index loop
         if Rec.Channels (Index).Loaded
           and then not Rec.Samples (Index).Is_Empty
           and then Rec.Channels (Index).Sampling_Rate > 0.0
         then
            Ref := Long_Float'Max (Ref, Rec.Channels (Index).Sampling_Rate);
            Span := Long_Float'Max
              (Span,
               Long_Float (Rec.Samples (Index).Length) /
                 Rec.Channels (Index).Sampling_Rate);
         end if;
      end loop;

      Ada.Text_IO.Create (Json, Ada.Text_IO.Out_File, Stem & ".json");
      Ada.Text_IO.Put_Line (Json, "{");
      Ada.Text_IO.Put_Line (Json, "  ""meddb_export_version"": 1,");
      Put_Json_String (Json, "name", To_String (Rec.Name), ",");
      Put_Json_String (Json, "format", To_String (Rec.Format_Name), ",");
      Put_Json_String (Json, "source", To_String (Rec.Source), ",");
      Put_Json_String (Json, "start_time", To_String (Rec.Start_Time), ",");
      Ada.Text_IO.Put_Line
        (Json, "  ""duration_s"": " & Types.Format_Number (Rec.Duration) & ",");
      Ada.Text_IO.Put_Line (Json, "  ""window"": {");
      Ada.Text_IO.Put_Line
        (Json, "    ""start_s"": " & Types.Format_Number (Rec.Window_Start) & ",");
      Ada.Text_IO.Put_Line
        (Json,
         "    ""duration_s"": " & Types.Format_Number (Rec.Window_Duration));
      Ada.Text_IO.Put_Line (Json, "  },");
      Ada.Text_IO.Put_Line
        (Json, "  ""csv_timebase_hz"": " & Types.Format_Number (Ref) & ",");
      Ada.Text_IO.Put_Line
        (Json,
         "  ""annotations_in_file"": " &
           Types.Trim (Natural'Image (Rec.Annotations_In_File)) & ",");
      Ada.Text_IO.Put_Line (Json, "  ""comments"": [");
      declare
         First : Boolean := True;
      begin
         for C of Rec.Comments loop
            if not First then
               Ada.Text_IO.Put_Line (Json, ",");
            end if;
            First := False;
            Ada.Text_IO.Put (Json, "    """ & Json_Escape (To_String (C)) & """");
         end loop;
         Ada.Text_IO.New_Line (Json);
      end;
      Ada.Text_IO.Put_Line (Json, "  ],");
      Ada.Text_IO.Put_Line (Json, "  ""channels"": [");
      declare
         First : Boolean := True;
      begin
         for Index in Rec.Channels.First_Index .. Rec.Channels.Last_Index loop
            declare
               Ch : constant Types.Channel := Rec.Channels (Index);
            begin
               if not First then
                  Ada.Text_IO.Put_Line (Json, ",");
               end if;
               First := False;
               Ada.Text_IO.Put_Line (Json, "    {");
               Ada.Text_IO.Put_Line
                 (Json,
                  "      ""index"": " &
                    Types.Trim (Integer'Image (Index)) & ",");
               Ada.Text_IO.Put_Line
                 (Json,
                  "      ""label"": """ & Json_Escape (To_String (Ch.Label)) & """,");
               Ada.Text_IO.Put_Line
                 (Json,
                  "      ""column"": """ &
                    Json_Escape (Column_Name (Rec, Index)) & """,");
               Ada.Text_IO.Put_Line
                 (Json,
                  "      ""units"": """ & Json_Escape (To_String (Ch.Units)) & """,");
               Ada.Text_IO.Put_Line
                 (Json,
                  "      ""sampling_rate_hz"": " &
                    Types.Format_Number (Ch.Sampling_Rate) & ",");
               Ada.Text_IO.Put_Line
                 (Json,
                  "      ""gain"": " & Types.Format_Number (Ch.Gain) & ",");
               Ada.Text_IO.Put_Line
                 (Json,
                  "      ""baseline"": " &
                    Types.Trim (Integer'Image (Ch.Baseline)) & ",");
               Ada.Text_IO.Put_Line
                 (Json,
                  "      ""physical_min"": " &
                    Types.Format_Number (Ch.Physical_Min) & ",");
               Ada.Text_IO.Put_Line
                 (Json,
                  "      ""physical_max"": " &
                    Types.Format_Number (Ch.Physical_Max) & ",");
               Ada.Text_IO.Put_Line
                 (Json,
                  "      ""n_samples_in_file"": " &
                    Types.Trim (Long_Long_Integer'Image (Ch.Samples_In_File)) & ",");
               Ada.Text_IO.Put_Line
                 (Json,
                  "      ""n_samples_exported"": " &
                    Types.Trim (Ada.Containers.Count_Type'Image
                      (Rec.Samples (Index).Length)) & ",");
               Ada.Text_IO.Put_Line
                 (Json,
                  "      ""exported"": " &
                    (if Ch.Loaded then "true" else "false") & ",");
               Ada.Text_IO.Put
                 (Json,
                  "      ""note"": """ & Json_Escape (To_String (Ch.Note)) & """");
               Ada.Text_IO.New_Line (Json);
               Ada.Text_IO.Put (Json, "    }");
            end;
         end loop;
         Ada.Text_IO.New_Line (Json);
      end;
      Ada.Text_IO.Put_Line (Json, "  ],");
      Ada.Text_IO.Put_Line (Json, "  ""annotations"": [");
      declare
         First : Boolean := True;
      begin
         for Ann of Rec.Annotations loop
            if not First then
               Ada.Text_IO.Put_Line (Json, ",");
            end if;
            First := False;
            Ada.Text_IO.Put_Line (Json, "    {");
            Ada.Text_IO.Put_Line
              (Json, "      ""onset_s"": " & Types.Format_Number (Ann.Onset) & ",");
            Ada.Text_IO.Put_Line
              (Json,
               "      ""duration_s"": " & Types.Format_Number (Ann.Duration) & ",");
            Ada.Text_IO.Put_Line
              (Json,
               "      ""label"": """ & Json_Escape (To_String (Ann.Label)) & """,");
            Ada.Text_IO.Put_Line
              (Json,
               "      ""channel"": """ &
                 Json_Escape (To_String (Ann.Channel)) & """,");
            Ada.Text_IO.Put
              (Json,
               "      ""description"": """ &
                 Json_Escape (To_String (Ann.Description)) & """");
            Ada.Text_IO.New_Line (Json);
            Ada.Text_IO.Put (Json, "    }");
         end loop;
         Ada.Text_IO.New_Line (Json);
      end;
      Ada.Text_IO.Put_Line (Json, "  ]");
      Ada.Text_IO.Put_Line (Json, "}");
      Ada.Text_IO.Close (Json);

      Ada.Text_IO.Create (Csv, Ada.Text_IO.Out_File, Stem & ".csv");
      Ada.Text_IO.Put (Csv, "time_s");
      for Index in Rec.Channels.First_Index .. Rec.Channels.Last_Index loop
         if Rec.Channels (Index).Loaded then
            Ada.Text_IO.Put (Csv, "," & Csv_Escape (Column_Name (Rec, Index)));
         end if;
      end loop;
      Ada.Text_IO.New_Line (Csv);
      if Ref > 0.0 and then Span > 0.0 then
         declare
            Rows : constant Natural :=
              Natural (Long_Float'Rounding (Span * Ref));
         begin
            for I in 0 .. Rows - 1 loop
               Ada.Text_IO.Put
                 (Csv,
                  Types.Format_Number
                    (Rec.Window_Start + Long_Float (I) / Ref, 9));
               for Index in Rec.Channels.First_Index .. Rec.Channels.Last_Index loop
                  if Rec.Channels (Index).Loaded then
                     declare
                        Ch    : constant Types.Channel := Rec.Channels (Index);
                        Data  : Types.Sample_Vectors.Vector renames
                          Rec.Samples (Index);
                        J     : Integer := -1;
                     begin
                        Ada.Text_IO.Put (Csv, ",");
                        if Ch.Sampling_Rate > 0.0 and then not Data.Is_Empty then
                           J := Integer
                             (Long_Float'Floor
                                (Long_Float (I) * Ch.Sampling_Rate / Ref));
                           if J in 0 .. Integer (Data.Length) - 1 then
                              Ada.Text_IO.Put
                                (Csv,
                                 Types.Format_Number
                                   (Data (Data.First_Index + J), 8));
                           end if;
                        end if;
                     end;
                  end if;
               end loop;
               Ada.Text_IO.New_Line (Csv);
            end loop;
         end;
      end if;
      Ada.Text_IO.Close (Csv);
   exception
      when Meddb.Error =>
         raise;
      when E : others =>
         if Ada.Text_IO.Is_Open (Json) then
            Ada.Text_IO.Close (Json);
         end if;
         if Ada.Text_IO.Is_Open (Csv) then
            Ada.Text_IO.Close (Csv);
         end if;
         raise Meddb.Error with "export failed: " &
           Ada.Exceptions.Exception_Message (E);
   end Write;

end Meddb.Export;
