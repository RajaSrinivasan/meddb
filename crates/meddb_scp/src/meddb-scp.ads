with Meddb.Types;

package Meddb.Scp is

   procedure Read
     (Path : String;
      Req  : Types.Read_Request;
      Rec  : out Types.Recording);

end Meddb.Scp;
