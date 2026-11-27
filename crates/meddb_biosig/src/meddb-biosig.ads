with Meddb.Types;

package Meddb.Biosig is

   procedure Read
     (Path        : String;
      Req         : Types.Read_Request;
      Expect      : String;
      Want_Events : Boolean;
      Rec         : out Types.Recording);

end Meddb.Biosig;
