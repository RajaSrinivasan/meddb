with Meddb.Types;

package Meddb.Mat is

   procedure Read
     (Path     : String;
      Req      : Types.Read_Request;
      Hea_Path : String;
      Rec      : out Types.Recording);

end Meddb.Mat;
