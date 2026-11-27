with Ada.Strings.Unbounded;

with Meddb.Types;

package Meddb.CLI is

   use Ada.Strings.Unbounded;

   type Options is record
      Start            : Long_Float := 0.0;
      Duration         : Long_Float := -1.0;
      Export_Prefix    : Unbounded_String;
      Full             : Boolean := False;
      Help             : Boolean := False;
      List_Only        : Boolean := False;
      Max_Print_Rows   : Natural := 6;
      Max_Print_Annots : Natural := 20;
      Annotator        : Unbounded_String := To_Unbounded_String ("atr");
      Companion        : Unbounded_String;
   end record;

   procedure Print_Usage (Tool : String);

   procedure Parse
     (Tool  : String;
      Opts  : out Options;
      Input : out Unbounded_String);

   function Request (Opts : Options) return Types.Read_Request;

   procedure Report (Rec : Types.Recording; Opts : Options);

end Meddb.CLI;
