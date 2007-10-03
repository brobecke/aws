------------------------------------------------------------------------------
--                              Ada Web Server                              --
--                                                                          --
--                          Copyright (C) 2006-2007                         --
--                                  AdaCore                                 --
--                                                                          --
--  This library is free software; you can redistribute it and/or modify    --
--  it under the terms of the GNU General Public License as published by    --
--  the Free Software Foundation; either version 2 of the License, or (at   --
--  your option) any later version.                                         --
--                                                                          --
--  This library is distributed in the hope that it will be useful, but     --
--  WITHOUT ANY WARRANTY; without even the implied warranty of              --
--  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU       --
--  General Public License for more details.                                --
--                                                                          --
--  You should have received a copy of the GNU General Public License       --
--  along with this library; if not, write to the Free Software Foundation, --
--  Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.          --
--                                                                          --
--  As a special exception, if other files instantiate generics from this   --
--  unit, or you link this unit with other files to produce an executable,  --
--  this  unit  does not  by itself cause  the resulting executable to be   --
--  covered by the GNU General Public License. This exception does not      --
--  however invalidate any other reasons why the executable file  might be  --
--  covered by the  GNU Public License.                                     --
------------------------------------------------------------------------------

--  Server push regression test

with Ada.Exceptions;
with Ada.Streams;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Ada.Text_IO.Editing;

with AWS.Client;
with AWS.Parameters;
with AWS.Response;
with AWS.Server.Push;
with AWS.Status;
with AWS.Translator;
with AWS.Utils;

package body Sp_Pack is

   use Ada;
   use Ada.Text_IO;
   use AWS;

   type Push_Data_Type is delta 0.01 digits 7;

   CRLF        : constant String := ASCII.CR & ASCII.LF;
   End_Of_Part : constant String := '.' & CRLF;

   function To_Array
     (Data : in Push_Data_Type;
      Env  : in Text_IO.Editing.Picture)
      return Ada.Streams.Stream_Element_Array;

   package Server_Push is new AWS.Server.Push
     (Client_Output_Type => Push_Data_Type,
      Client_Environment => Text_IO.Editing.Picture,
      To_Stream_Array    => To_Array);

   function CB (Request : in Status.Data) return Response.Data;

   Push : Server_Push.Object;

   --------
   -- CB --
   --------

   function CB (Request : in Status.Data) return Response.Data is
      use AWS.Parameters;

      function "+" (Item : in String)
         return Ada.Strings.Unbounded.Unbounded_String
        renames Ada.Strings.Unbounded.To_Unbounded_String;

      P_List     : constant List := AWS.Status.Parameters (Request);
      CID_Image  : constant String   := Get (P_List, "CID");
      CID        : constant Positive := Positive'Value (CID_Image);
      Mode_Value : constant Server_Push.Mode
         := Server_Push.Mode'Val
              (CID rem (Server_Push.Mode'Pos (Server_Push.Mode'Last) + 1));
      GID0       : constant String := "Dummy";
      GID1       : constant String := Boolean'Image (CID rem 2 = 0);
      GID2       : constant String := Integer'Image (CID rem 5);

      Picture : array (Server_Push.Mode) of Editing.Picture
        := (Server_Push.Plain     => Editing.To_Picture ("zzzzz9.99"),
            Server_Push.Chunked   => Editing.To_Picture ("999999.99"),
            Server_Push.Multipart => Editing.To_Picture ("###_##9.99"));
   begin
      Server_Push.Register
        (Server            => Push,
         Client_ID         => CID_Image,
         Groups            => (+GID0, +GID1),
         Init_Data         => 0.01,
         Init_Content_Type => "text/number",
         Socket            => AWS.Status.Socket (Request),
         Environment       => Picture (Mode_Value),
         Kind              => Mode_Value);

      Server_Push.Subscribe (Push, Client_Id => CID_Image, Group_Id => GID2);
      Server_Push.Unsubscribe (Push, Client_Id => CID_Image, Group_Id => GID0);

      --  Marker to be sure that group message receive would be after
      --  Subscribe/Unsubscribe.

      Server_Push.Send_To (Push, CID_Image, 0.02, "text/number");

      return Response.Socket_Taken;
   end CB;

   --------------
   -- To_Array --
   --------------

   function To_Array
     (Data : in Push_Data_Type;
      Env  : in Text_IO.Editing.Picture)
      return Ada.Streams.Stream_Element_Array
   is
      package Format is new Text_IO.Editing.Decimal_Output (Push_Data_Type);
   begin
      return Translator.To_Stream_Element_Array
               (Format.Image (Data, Env) & End_Of_Part);
   end To_Array;

   ---------
   -- Run --
   ---------

   procedure Run (Protocol : in String; Port : in Positive) is
      Connect : array (1 .. 30) of Client.HTTP_Connection;
      Answer  : AWS.Response.Data;
      Data    : Push_Data_Type;

      HTTP : AWS.Server.HTTP;
      URL  : constant String
        := Protocol & "://localhost:" & AWS.Utils.Image (Port);

      procedure Output (Data : String);
      --  Ignore random string --AWS.Push.Boundary_1044468257,
      --  and by the way ignore ASCII.CR because on the Win32 platform
      --  the Ada.Text_IO.Put_Line add the ASCII.CR before ASCII.LF even so
      --  the ASCII.CR already exists before ASCII.LF.

      ------------
      -- Output --
      ------------

      procedure Output (Data : in String) is
         Ignore_Sample : constant String := "--AWS.Push.Boundary_";
         use Ada.Strings;
         First : Positive := Data'First;
         Index : Natural;
      begin
         loop
            Index := Fixed.Index (Data (First .. Data'Last), CRLF);
            if Index = 0 then
               Put (Data (First .. Data'Last));
               exit;
            else
               if Index - First < Ignore_Sample'Length
                 or else Data (First .. First + Ignore_Sample'Length - 1)
                          /= Ignore_Sample
               then
                  Put_Line (Data (First .. Index - 1));
               end if;
               First := Index + CRLF'Length;
            end if;
            exit when First > Data'Last;
         end loop;
      end Output;

   begin
      AWS.Server.Start
        (HTTP,
         "Testing server push.",
         CB'Access,
         Port           => Port,
         Security       => Protocol = "https",
         Max_Connection => 3);

      Data := 1000.0;

      --  Initialize all the push connections

      for J in Connect'Range loop
         Client.Create
           (Connection  => Connect (J),
            Host        => URL,
            Timeouts    => (15.0, 15.0),
            Server_Push => True);

         Client.Get (Connect (J), Answer, "/uri?CID=" & Utils.Image (J));

         Output (Client.Read_Until (Connect (J), End_Of_Part));
      end loop;

      --  Receive subscribe/unsubscribe marker

      for J in Connect'Range loop
         if Strings.Fixed.Index
              (Client.Read_Until (Connect (J), End_Of_Part), "0.02") = 0
         then
            Ada.Text_IO.Put_Line ("Marker error.");
         end if;
      end loop;

      --  Send some data

      for K in 1 .. 2 loop

         Data := Data + 1.0;

         Server_Push.Send (Push, Data => Data, Content_Type => "broadcast");

         for J in Connect'Range loop
            Put_Line ("----");
            Output (Client.Read_Until (Connect (J), End_Of_Part));

            Data := Data + 0.01;

            Server_Push.Send_To (Push, Utils.Image (J), Data, "exact");

            Output (Client.Read_Until (Connect (J), End_Of_Part));
         end loop;

      end loop;

      Data := 0.00;

      for J in 0 .. 4 loop
         Data := Data + 11_111.11;

         Server_Push.Send
           (Push,
            Group_Id     => Integer'Image (J),
            Data         => Data,
            Content_Type => "group-5");
      end loop;

      Data := 0.00;

      for J in Boolean'Range loop
         Data := Data + 11.11;

         Server_Push.Send
           (Push,
            Group_Id     => Boolean'Image (J),
            Data         => Data,
            Content_Type => "group-boolean");
      end loop;

      for J in Connect'Range loop
         Put_Line ("---");
         Output (Client.Read_Until (Connect (J), End_Of_Part));
         Output (Client.Read_Until (Connect (J), End_Of_Part));
      end loop;

      for J in Connect'Range loop
         --  Next line will automatically unregister server push clients,
         --  closed in previous iterations.
         --  Last connection would not be unregistered.

         Server_Push.Send (Push, Data => Data, Content_Type => "text/plain");

         Client.Close (Connect (J));
      end loop;

      if Server_Push.Count (Push) > 1 then
         --  Wait for server-push internal waiter process completion.
         delay 0.5;
      end if;

      if Server_Push.Count (Push) /= 1 then
         Put_Line ("Auto unregister error." & Server_Push.Count (Push)'Img);
      end if;

      Server_Push.Unregister_Clients (Push);

   exception
      when E : others =>
         Ada.Text_IO.Put_Line (Ada.Exceptions.Exception_Information (E));
   end Run;

end Sp_Pack;
