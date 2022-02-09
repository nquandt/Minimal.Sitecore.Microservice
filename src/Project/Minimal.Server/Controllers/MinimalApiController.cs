using System;
using System.Collections.Generic;
using System.Linq;
using System.Web;
using System.Web.Http;

namespace Minimal.Server.Controllers
{
    public class MinimalApiController : ApiController
    {
        [HttpGet]
        [Route("/api/testing")]
        public string Get(string input)
        {


            return "";
        }
    }
}