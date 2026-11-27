with Ada.Command_Line;
with Ada.Containers;
with Ada.Strings.Unbounded;
with Ada.Text_IO;

with Meddb.Export;
with Meddb.Types;

package body Meddb.CLI is

   use Ada.Strings.Unbounded;
   use Ada.Text_IO;

   procedure Print_Usage (Tool : String) is
   begin
      Put_Line ("usage: " & Tool & " INPUT [options]");
      Put_Line ("  --start SEC          sample window start (default 0)");
      Put_Line ("  --duration SEC       sample window length");
      Put_Line ("  --full               load the recording instead of a short window");
      Put_Line ("  --export PREFIX      write PREFIX.csv and PREFIX.json");
      Put_Line ("  --annotator NAME     WFDB annotator (default atr)");
      Put_Line ("  --hypnogram FILE     companion EDF+ annotation file");
      Put_Line ("  --hea FILE           companion WFDB header for a .mat file");
      Put_Line ("  --list-only          print container structure and exit");
      Put_Line ("  --help");
      Put_Line ("Without --duration or --full, a " &
        Types.Format_Number (Types.Default_Window_Seconds) &
        " s window is loaded.");
      Put_Line ("Channels faster than " &
        Types.Format_Number (Types.Fast_Rate_Hz) &
        " Hz are listed but not loaded unless --duration or --full is set.");
   end Print_Usage;

   function Need (Flag : String; Index : Positive) return String is
   begin
      if Index > Ada.Command_Line.Argument_Count then
         raise Meddb.Error with Flag & " needs a value";
      end if;
      return Ada.Command_Line.Argument (Index);
   end Need;

   procedure Parse
     (Tool  : String;
      Opts  : out Options;
      Input : out Unbounded_String)
   is
      pragma Unreferenced (Tool);
      I : Positive := 1;
   begin
      Opts := (others => <>);
      Opts.Annotator := To_Unbounded_String ("atr");
      Input := Null_Unbounded_String;
      while I <= Ada.Command_Line.Argument_Count loop
         declare
            A : constant String := Ada.Command_Line.Argument (I);
         begin
            if A in "--help" | "-h" then
               Opts.Help := True;
            elsif A = "--full" then
               Opts.Full := True;
            elsif A = "--list-only" then
               Opts.List_Only := True;
            elsif A = "--start" then
               I := I + 1;
               Opts.Start := Long_Float'Value (Need ("--start", I));
            elsif A = "--duration" then
               I := I + 1;
               Opts.Duration := Long_Float'Value (Need ("--duration", I));
            elsif A = "--export" then
               I := I + 1;
               Opts.Export_Prefix := To_Unbounded_String (Need ("--export", I));
            elsif A = "--annotator" then
               I := I + 1;
               Opts.Annotator := To_Unbounded_String (Need ("--annotator", I));
            elsif A in "--hypnogram" | "--annotations" | "--hea" then
               I := I + 1;
               Opts.Companion := To_Unbounded_String (Need (A, I));
            elsif A'Length > 0 and then A (A'First) = '-' then
               raise Meddb.Error with "unknown option " & A;
            else
               if Input /= "" then
                  raise Meddb.Error with "unexpected argument " & A;
               end if;
               Input := To_Unbounded_String (A);
            end if;
         end;
         I := I + 1;
      end loop;
   exception
      when Constraint_Error =>
         raise Meddb.Error with "invalid numeric option";
   end Parse;

   function Request (Opts : Options) return Types.Read_Request is
   begin
      return
        (Start    => Opts.Start,
         Duration => Opts.Duration,
         Full     => Opts.Full);
   end Request;

   procedure Report (Rec : Types.Recording; Opts : Options) is
      Shown : Natural := 0;
   begin
      if not Rec.Structure.Is_Empty then
         Put_Line ("structure:");
         for Node of Rec.Structure loop
            Put ("  " & To_String (Node.Path));
            Put ("  " & To_String (Node.Dtype));
            Put ("  rank=" & Types.Trim (Natural'Image (Node.Rank)));
            Put ("  shape=");
            for D in 1 .. Node.Rank loop
               if D > 1 then
                  Put ("x");
               end if;
               Put (Types.Trim (Long_Long_Integer'Image (Node.Dims (D))));
            end loop;
            New_Line;
         end loop;
      end if;
      if Opts.List_Only then
         return;
      end if;

      Put_Line ("record: " & To_String (Rec.Name));
      Put_Line ("format: " & To_String (Rec.Format_Name));
      Put_Line ("source: " & To_String (Rec.Source));
      if Rec.Start_Time /= "" then
         Put_Line ("start_time: " & To_String (Rec.Start_Time));
      end if;
      Put_Line ("duration_s: " & Types.Format_Number (Rec.Duration));
      Put_Line ("channels: " & Types.Trim (Natural'Image
        (Natural (Rec.Channels.Length))));
      for Index in Rec.Channels.First_Index .. Rec.Channels.Last_Index loop
         declare
            Ch : constant Types.Channel := Rec.Channels (Index);
         begin
            Put ("channel: " & Types.Trim (Integer'Image (Index)));
            Put (" label=" & To_String (Ch.Label));
            Put (" units=" & To_String (Ch.Units));
            Put (" fs=" & Types.Format_Number (Ch.Sampling_Rate));
            Put (" n=" & Types.Trim (Long_Long_Integer'Image (Ch.Samples_In_File)));
            if Ch.Gain /= 0.0 then
               Put (" gain=" & Types.Format_Number (Ch.Gain));
            end if;
            Put (" baseline=" & Types.Trim (Integer'Image (Ch.Baseline)));
            if Ch.Loaded then
               Put (" loaded=" & Types.Trim (Ada.Containers.Count_Type'Image
                 (Rec.Samples (Index).Length)));
            elsif Ch.Note /= "" then
               Put (" note=" & To_String (Ch.Note));
            else
               Put (" loaded=0");
            end if;
            New_Line;
         end;
      end loop;
      Put_Line ("annotations: " & Types.Trim (Natural'Image
        (Rec.Annotations_In_File)));
      Shown := 0;
      for Ann of Rec.Annotations loop
         exit when Shown >= Opts.Max_Print_Annots;
         Put ("annotation: onset_s=" & Types.Format_Number (Ann.Onset));
         Put (" duration_s=" & Types.Format_Number (Ann.Duration));
         Put (" label=" & To_String (Ann.Label));
         if Ann.Description /= "" and then Ann.Description /= Ann.Label then
            Put (" description=" & To_String (Ann.Description));
         end if;
         New_Line;
         Shown := Shown + 1;
      end loop;
      for C of Rec.Comments loop
         Put_Line ("comment: " & To_String (C));
      end loop;
      Put_Line ("window_start_s: " & Types.Format_Number (Rec.Window_Start));
      Put_Line ("window_duration_s: " & Types.Format_Number (Rec.Window_Duration));
      Shown := 0;
      if Types.Loaded_Count (Rec) > 0 then
         declare
            Rows : Natural := Natural'Last;
         begin
            for Index in Rec.Channels.First_Index .. Rec.Channels.Last_Index loop
               if Rec.Channels (Index).Loaded then
                  Rows := Natural'Min
                    (Rows, Natural (Rec.Samples (Index).Length));
               end if;
            end loop;
            Rows := Natural'Min (Rows, Opts.Max_Print_Rows);
            for I in 1 .. Rows loop
               Put ("sample:");
               for Index in Rec.Channels.First_Index .. Rec.Channels.Last_Index loop
                  if Rec.Channels (Index).Loaded
                    and then I <= Natural (Rec.Samples (Index).Length)
                  then
                     Put (" " & To_String (Rec.Channels (Index).Label) & "=" &
                       Types.Format_Number
                         (Rec.Samples (Index) (Rec.Samples (Index).First_Index
                            + I - 1), 6));
                  end if;
               end loop;
               New_Line;
            end loop;
         end;
      end if;
      if Opts.Export_Prefix /= "" then
         Export.Write (Rec, To_String (Opts.Export_Prefix));
         Put_Line ("export: " & To_String (Opts.Export_Prefix) & ".csv");
         Put_Line ("export: " & To_String (Opts.Export_Prefix) & ".json");
      end if;
   end Report;

end Meddb.CLI;
