------------------------------------------------------------------------------
--                              Ada Web Server                              --
--                                                                          --
--                         Copyright (C) 2000-2004                          --
--                                ACT-Europe                                --
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

--  $Id$

--  See main.adb on how to run this demo.

with Ada.Command_Line;
with Ada.Text_IO;

with AWS.Client.Hotplug;
with AWS.Messages;
with AWS.Net;
with AWS.Response;
with AWS.Server;

with Hotplug_CB;

procedure Hotplug is

   use Ada;
   use type AWS.Messages.Status_Code;

   procedure Wait_Terminate;
   --  Wait for module to terminate and unregister it

   Response : AWS.Response.Data;

   Filter   : constant String := ".*AWS.*";

   Password : constant String := "pwd";
   --  Note that in secure applications this password with be get from the
   --  standard input.

   --------------------
   -- Wait_Terminate --
   --------------------

   procedure Wait_Terminate is
      C : Character;
   begin
      loop
         Text_IO.Get_Immediate (C);
         exit when C = 'T';
      end loop;

      Response := AWS.Client.Hotplug.Unregister
        ("hp_demo", Password,
         "http://" & Command_Line.Argument (1) & ":2222", Filter);

      if AWS.Response.Status_Code (Response) /= AWS.Messages.S200 then
         Text_IO.Put_Line
           ("Unregister Error : " & AWS.Response.Message_Body (Response));
      end if;
   end Wait_Terminate;

   WS : AWS.Server.HTTP;

begin
   if Command_Line.Argument_Count /= 1 then
      Text_IO.Put_Line ("Syntax: hotplug <main_server_hostname>");
      Text_IO.New_Line;
      return;
   end if;

   Text_IO.Put_Line ("AWS " & AWS.Version);
   Text_IO.Put_Line ("Enter T to terminate...");
   Text_IO.Put_Line
     ("Hotplug module linked to server " & Command_Line.Argument (1));

   AWS.Server.Start
     (WS, "Hotplug",
      Admin_URI      => "/Admin-Page",
      Port           => 1235,
      Max_Connection => 3,
      Callback       => Hotplug_CB.Hotplug'Access);

   Response := AWS.Client.Hotplug.Register
     ("hp_demo", Password,
      "http://" & Command_Line.Argument (1) & ":2222",
      Filter, "http://" & AWS.Net.Host_Name & ":1235/");

   if AWS.Response.Status_Code (Response) = AWS.Messages.S200 then
      Wait_Terminate;
   else
      Text_IO.Put_Line
        ("Register Error : " & AWS.Response.Message_Body (Response));
   end if;

   AWS.Server.Shutdown (WS);
end Hotplug;
