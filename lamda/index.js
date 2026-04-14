import { DynamoDBClient } from "@aws-sdk/client-dynamodb";
import {
  DynamoDBDocumentClient,
  GetCommand,
  PutCommand
} from "@aws-sdk/lib-dynamodb";
import { randomBytes } from "crypto";

const client = new DynamoDBClient({});
const ddb = DynamoDBDocumentClient.from(client);

const TABLE_NAME = process.env.TABLE_NAME;

function generateCode() {
  return randomBytes(4).toString("hex");
}

export const handler = async (event) => {
  const method = event.requestContext.http.method;

  // CREATE SHORT URL
  if (method === "POST") {
    const body = JSON.parse(event.body);
    const code = generateCode();

    await ddb.send(
      new PutCommand({
        TableName: TABLE_NAME,
        Item: {
          code,
          originalUrl: body.url,
          createdAt: Date.now()
        }
      })
    );

    return {
      statusCode: 201,
      body: JSON.stringify({
        shortUrl: `${process.env.BASE_URL}/${code}`
      })
    };
  }

  // REDIRECT
  const code = event.pathParameters?.code;

  const data = await ddb.send(
    new GetCommand({
      TableName: TABLE_NAME,
      Key: { code }
    })
  );

  if (!data.Item) {
    return { statusCode: 404, body: "Not Found" };
  }

  return {
    statusCode: 302,
    headers: { Location: data.Item.originalUrl }
  };
};
