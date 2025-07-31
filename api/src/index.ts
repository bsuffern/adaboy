import express, { Express, Request, Response, NextFunction } from "express";
import dotenv from "dotenv";
import cors from "cors";
import bodyParser from "body-parser";
import { connectToDatabase } from "./services/database";
import { CreateEthFusionOrderHandler } from "./features/CreateEthFusionOrderHandler";
import { BaseError } from "new-error";

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

app.listen(port, () => {
	console.log(`Example app listening on port ${port}`);
});

const tryCatch = async (
	req: Request,
	res: Response,
	next: NextFunction,
	func: any
) => {
	try {
		await func(req, res);
	} catch (err: any) {
		next(err);
	}
};

connectToDatabase()
	.then(() => {
		// Root
		app.get("/", (req: Request, res: Response) => {
			res.send("AdaBoy API");
		});

		// Create fusion order on ethereum
		app.post(
			"/orders/eth",
			(req: Request, res: Response, next: NextFunction) =>
				tryCatch(req, res, next, CreateEthFusionOrderHandler)
		);

		app.use((err: any, req: any, res: any, next: any) => {
			// error was sent from middleware
			if (err) {
				console.log(err);
				// check if the error is a generated one
				if (err instanceof BaseError) {
					// generate an error id
					err.withErrorId(Math.random().toString(36).slice(2));

					// log the error and format it
					console.error(JSON.stringify(err.toJSON(), null, 2));

					// get the status code, defaults to 500
					res.status(err.getStatusCode() ?? 500);

					// push error to client
					return res.json({
						err: err.toJSONSafe()
					});
				}

				// push error to client
				return res.json({
					err: {
						message: err.message
					}
				});
			}

			// no error, proceed
			next();
		});

		app.listen(port, () => {
			console.log(
				`[server]: Server is running at http://localhost:${port}`
			);
		});
	})
	.catch((error: Error) => {
		console.error("Database connection failed", error);
		process.exit();
	});
