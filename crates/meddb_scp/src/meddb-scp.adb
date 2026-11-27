with Ada.Strings.Unbounded;

with Meddb.Biosig;

package body Meddb.Scp is

   use Ada.Strings.Unbounded;

   procedure Read
     (Path : String;
      Req  : Types.Read_Request;
      Rec  : out Types.Recording)
   is
   begin
      Biosig.Read (Path, Req, "SCP", True, Rec);
      Rec.Format_Name := To_Unbounded_String ("scp-ecg");
   end Read;

end Meddb.Scp;
