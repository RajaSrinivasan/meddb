with Meddb.Types;

package Meddb.Aecg is

   procedure Read
     (Path : String;
      Req  : Types.Read_Request;
      Rec  : out Types.Recording);

end Meddb.Aecg;
