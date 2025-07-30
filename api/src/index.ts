import express, { Express, Request, Response, NextFunction } from "express";
import dotenv from "dotenv";
import cors from "cors";
import bodyParser from "body-parser";

dotenv.config();

// APP SETTINGS
const app: Express = express();
app.use(express.json({ limit: "50mb" }));

const corsOptions = {
    origin: process.env.CORS_ALLOWED_ORIGIN
};

app.use(cors(corsOptions));
app.use(bodyParser.json());

const port = process.env.PORT || 3000;

app.get("/", (req: Request, res: Response) => {
    res.send("AdaBoy API");
});

app.listen(port, () => {
  console.log(`Example app listening on port ${port}`)
})